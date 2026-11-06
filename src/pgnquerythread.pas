// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnQueryThread;

{ Runs one or more statements off the UI thread so the window never
  freezes while the database works. When finished it calls OnDone on the
  main thread, then frees itself.

  Every result set that comes back is kept, in order (a script's SELECTs,
  a CALL's several sets), up to MaxResultSets; the receiver takes them with
  TakeResults. Anything not taken is freed with the thread.

  Current says which statement is running, so the window can show
  progress through a long script. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, pgnTypes, pgnAdapter, pgnSqlSplit;

const
  MaxResultSets = 20;

type
  TpgnQueryThread = class(TThread)
  private
    FAdapter: TpgnAdapter;
    FStatements: TpgnStringArray;
    FRowLimit: Integer;
    FOnDone: TNotifyEvent;
    FResults: TFPList;           // of TpgnResultSet (single, unchained)
    FDropped: Integer;           // result sets beyond MaxResultSets
    FMessages: TStringList;
    FErrorText: string;
    FErrorIndex: Integer;        // 1-based statement that failed; 0 = none
    FElapsedMs: QWord;
    FExecuted: Integer;
    FCurrent: Integer;           // 1-based statement running now
    FStopped: Boolean;           // canceled between statements
    FAffected: array of Int64;   // per statement: rows changed (-1: it returned rows)
    FSavepoints: TpgnStringArray;   // per statement: the savepoint set before it, or ''
    FSavepointBase: string;
    FSavepointStart: Integer;
    FSavepointAll: Boolean;
    FTransactionalDDL: Boolean;
    FFreshSnapshot: Boolean;
    procedure DoDone;
    procedure Keep(R: TpgnResultSet; const ASQL: string);
  protected
    procedure Execute; override;
  public
    constructor Create(AAdapter: TpgnAdapter; const AStatements: TpgnStringArray;
      ARowLimit: Integer; AOnDone: TNotifyEvent);
    destructor Destroy; override;
    { Hands over the result sets (the caller frees them and the list). }
    function TakeResults: TFPList;
    property Messages: TStringList read FMessages;
    property ErrorText: string read FErrorText;
    property ErrorIndex: Integer read FErrorIndex;
    property ElapsedMs: QWord read FElapsedMs;
    property Statements: TpgnStringArray read FStatements;
    property ExecutedCount: Integer read FExecuted;   // statements that succeeded
    property Current: Integer read FCurrent;
    property Stopped: Boolean read FStopped;
    property DroppedResults: Integer read FDropped;
    { Auto-commit off: a savepoint (base + number) goes before each statement
      that changes data, so it can be undone on its own later, or right
      away if it fails. '' = none. Set before Start. }
    property SavepointBase: string read FSavepointBase write FSavepointBase;
    property SavepointStart: Integer read FSavepointStart write FSavepointStart;
    { A savepoint before reads too (PostgreSQL's On error, roll back): an
      error then undoes only its statement. }
    property SavepointAll: Boolean read FSavepointAll write FSavepointAll;
    { PostgreSQL: DDL waits for Commit too, so it gets a savepoint. }
    property TransactionalDDL: Boolean read FTransactionalDDL write FTransactionalDDL;
    { MySQL, auto-commit off, nothing pending: end the reads-only transaction
      first, so this run sees what other sessions have committed since. }
    property FreshSnapshot: Boolean read FFreshSnapshot write FFreshSnapshot;
    function Affected(AIndex: Integer): Int64;
    function SavepointOf(AIndex: Integer): string;
  end;

implementation

constructor TpgnQueryThread.Create(AAdapter: TpgnAdapter; const AStatements: TpgnStringArray;
  ARowLimit: Integer; AOnDone: TNotifyEvent);
begin
  inherited Create(True);   // created suspended; the caller calls Start
  FreeOnTerminate := True;
  FAdapter := AAdapter;
  FStatements := Copy(AStatements);
  FRowLimit := ARowLimit;
  FOnDone := AOnDone;
  FResults := TFPList.Create;
  FDropped := 0;
  FMessages := TStringList.Create;
  FErrorText := '';
  FErrorIndex := 0;
  FExecuted := 0;
  FCurrent := 0;
  FStopped := False;
end;

destructor TpgnQueryThread.Destroy;
var
  I: Integer;
begin
  if FResults <> nil then
  begin
    for I := 0 to FResults.Count - 1 do
    begin
      TpgnResultSet(FResults[I]).Free;
    end;
    FResults.Free;
  end;
  FreeAndNil(FMessages);
  inherited Destroy;
end;

function TpgnQueryThread.Affected(AIndex: Integer): Int64;
begin
  Result := -1;
  if (AIndex >= 0) and (AIndex <= High(FAffected)) then
  begin
    Result := FAffected[AIndex];
  end;
end;

function TpgnQueryThread.SavepointOf(AIndex: Integer): string;
begin
  Result := '';
  if (AIndex >= 0) and (AIndex <= High(FSavepoints)) then
  begin
    Result := FSavepoints[AIndex];
  end;
end;

function TpgnQueryThread.TakeResults: TFPList;
begin
  Result := FResults;
  FResults := TFPList.Create;
end;

{ Keeps a result set and everything chained after it, one by one. }
procedure TpgnQueryThread.Keep(R: TpgnResultSet; const ASQL: string);
var
  Item: TpgnResultSet;
  K: Integer;
begin
  K := 0;
  while R <> nil do
  begin
    Item := R;
    R := R.Next;
    Item.Next := nil;
    Item.SourceSQL := ASQL;
    Item.SourceIndex := K;
    Inc(K);
    if FResults.Count < MaxResultSets then
    begin
      FResults.Add(Item);
    end
    else
    begin
      Inc(FDropped);
      Item.Free;
    end;
  end;
end;

procedure TpgnQueryThread.Execute;
var
  I, Sets: Integer;
  StartTick: QWord;
  R: TpgnResultSet;
  More, SP: string;
begin
  StartTick := GetTickCount64;
  SetLength(FAffected, Length(FStatements));
  SetLength(FSavepoints, Length(FStatements));
  for I := 0 to High(FStatements) do
  begin
    FAffected[I] := -1;
    FSavepoints[I] := '';
  end;
  if FFreshSnapshot then
  begin
    try
      FAdapter.Commit;   // nothing to commit: only reads since the last end
    except
      on E: Exception do
      begin
        FMessages.Add('Could not refresh the read view: ' + E.Message);
      end;
    end;
  end;
  for I := 0 to High(FStatements) do
  begin
    if Terminated then
    begin
      FStopped := True;
      FMessages.Add('Canceled before statement ' + IntToStr(I + 1) + ' of ' +
        IntToStr(Length(FStatements)));
      Break;
    end;
    FCurrent := I + 1;

    if (FSavepointBase <> '') and (FSavepointAll or StatementChangesData(FStatements[I]) or
      (FTransactionalDDL and StatementIsDDL(FStatements[I]))) then
    begin
      SP := FSavepointBase + IntToStr(FSavepointStart + I);
      try
        FAdapter.Execute('SAVEPOINT ' + SP, 0).Free;
        FSavepoints[I] := SP;
      except
        on E: Exception do
        begin
          FSavepoints[I] := '';   // the statement still runs; it just can't be undone alone
        end;
      end;
    end;

    R := nil;
    try
      R := FAdapter.Execute(FStatements[I], FRowLimit);
    except
      on E: Exception do
      begin
        FErrorText := Format('Statement %d: %s', [I + 1, E.Message]);
        FErrorIndex := I + 1;
        // undo just the failed statement: earlier pending work stays
        // (PostgreSQL would otherwise refuse everything until a rollback)
        if FSavepoints[I] <> '' then
        begin
          try
            FAdapter.Execute('ROLLBACK TO SAVEPOINT ' + FSavepoints[I], 0).Free;
            FMessages.Add(Format('Statement %d was undone on its own; the transaction is still open and ' +
              'earlier uncommitted changes are kept.', [I + 1]));
          except
            on E2: Exception do
            begin
              // the transaction stays as the database left it
            end;
          end;
          FSavepoints[I] := '';
        end;
        Break;
      end;
    end;

    Inc(FExecuted);
    // a read's savepoint isn't needed once it has run
    if FSavepointAll and (FSavepoints[I] <> '') and not StatementChangesData(FStatements[I]) and
      not (FTransactionalDDL and StatementIsDDL(FStatements[I])) then
    begin
      try
        FAdapter.Execute('RELEASE SAVEPOINT ' + FSavepoints[I], 0).Free;
      except
        on E: Exception do
        begin
          // harmless: it ends with the transaction
        end;
      end;
      FSavepoints[I] := '';
    end;
    // what the server said along the way (SQL Server's PRINT, row counts)
    for Sets := 0 to High(R.Messages) do
    begin
      FMessages.Add(R.Messages[Sets]);
    end;
    if R.ReturnsRows then
    begin
      if R.HasMoreRows then
      begin
        More := ' (row limit reached, more available)';
      end
      else
      begin
        More := '';
      end;
      Sets := R.ChainLength;
      if Sets > 1 then
      begin
        More := More + Format(' (%d result sets)', [Sets]);
      end;
      FMessages.Add(Format('Statement %d: %d row(s) fetched%s', [I + 1, R.RowCount, More]));
      Keep(R, FStatements[I]);
    end
    else
    begin
      FMessages.Add(Format('Statement %d: %d row(s) affected', [I + 1, R.RowsAffected]));
      FAffected[I] := R.RowsAffected;
      R.Free;
    end;
  end;
  FElapsedMs := GetTickCount64 - StartTick;
  Synchronize(@DoDone);
end;

procedure TpgnQueryThread.DoDone;
begin
  if Assigned(FOnDone) then
  begin
    FOnDone(Self);
  end;
end;

end.
