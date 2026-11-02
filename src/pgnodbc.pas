// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnOdbc;

{ A small ODBC client for Pagona's SQL Server adapter: connect with a
  driver connection string, run a batch, read every result set, the row
  counts and the server's messages (PRINT, "Changed database context"),
  and cancel from another thread.

  The ODBC driver manager is loaded at run time (odbc32.dll on Windows,
  libodbc.so.2 on Linux), so Pagona starts without it. Everything goes
  through the wide (UTF-16) calls; SQLWCHAR is two bytes on Windows and in
  unixODBC alike.

  One TpgnOdbcConnection is used by one thread at a time; Cancel may be
  called from any thread while Run is busy (ODBC allows SQLCancel so). }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, SyncObjs, DynLibs, pgnTypes;

type
  EpgnOdbcError = class(Exception)
  public
    SqlState: string;     // of the first diagnostic record
    NativeError: Integer;
  end;

  TpgnOdbcConnection = class
  private
    FDbc: Pointer;
    FStmt: Pointer;          // the statement Run is busy with
    FLock: TCriticalSection;
    procedure Check(ARet: SmallInt; AHandleType: SmallInt; AHandle: Pointer; const AWhat: string);
  public
    constructor Create;
    destructor Destroy; override;
    // AConnStr: Driver=(name in braces);Server=...;...
    procedure Connect(const AConnStr: string);
    procedure Disconnect;
    function Connected: Boolean;
    { Runs one batch. Every result set comes back (each up to ARowLimit
      rows, 0 = no limit), the first in the result, later ones on Next;
      the server's messages are on the first. Raises EpgnOdbcError (with
      the messages that came before the error) when the batch fails. }
    function Run(const ASQL: string; ARowLimit: Integer): TpgnResultSet;
    { Asks the server to stop the batch Run is running. }
    procedure Cancel;
  end;

{ Loads the driver manager once; raises with a plain explanation if it
  isn't there. }
procedure LoadOdbc;

implementation

const
  SQL_HANDLE_ENV = 1;
  SQL_HANDLE_DBC = 2;
  SQL_HANDLE_STMT = 3;
  SQL_SUCCESS = 0;
  SQL_SUCCESS_WITH_INFO = 1;
  SQL_NO_DATA = 100;
  SQL_ERROR = -1;
  SQL_INVALID_HANDLE = -2;
  SQL_NTS = -3;
  SQL_NULL_DATA = -1;
  SQL_NO_TOTAL = -4;
  SQL_ATTR_ODBC_VERSION = 200;
  SQL_OV_ODBC3 = 3;
  SQL_ATTR_LOGIN_TIMEOUT = 103;
  SQL_DRIVER_NOPROMPT = 0;
  SQL_C_WCHAR = -8;
  SQL_C_BINARY = -2;
  SQL_BINARY = -2;
  SQL_VARBINARY = -3;
  SQL_LONGVARBINARY = -4;
  SQL_SS_UDT = -151;
  SQL_CLOSE = 0;
  // SQL Server's own diagnostic fields (msodbcsql.h)
  SQL_DIAG_SS_MSGSTATE = -1150;
  SQL_DIAG_SS_SEVERITY = -1151;
  SQL_DIAG_SS_LINE = -1154;

type
  SQLRETURN = SmallInt;
  SQLLEN = PtrInt;
  SQLULEN = PtrUInt;
  PSQLLEN = ^SQLLEN;

  TAllocHandle = function(AType: SmallInt; AInput: Pointer; out AOutput: Pointer): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TFreeHandle = function(AType: SmallInt; AHandle: Pointer): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TSetEnvAttr = function(AEnv: Pointer; AAttr: LongInt; AValue: Pointer; ALen: LongInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TSetConnectAttr = function(ADbc: Pointer; AAttr: LongInt; AValue: Pointer; ALen: LongInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TDriverConnectW = function(ADbc: Pointer; AWnd: Pointer; AIn: PWideChar; AInLen: SmallInt;
    AOut: PWideChar; AOutMax: SmallInt; out AOutLen: SmallInt; ACompletion: Word): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TDisconnect = function(ADbc: Pointer): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TExecDirectW = function(AStmt: Pointer; AText: PWideChar; ALen: LongInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TNumResultCols = function(AStmt: Pointer; out ACount: SmallInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TDescribeColW = function(AStmt: Pointer; ACol: Word; AName: PWideChar; ANameMax: SmallInt;
    out ANameLen: SmallInt; out AType: SmallInt; out ASize: SQLULEN; out ADigits: SmallInt;
    out ANullable: SmallInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TFetch = function(AStmt: Pointer): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TGetData = function(AStmt: Pointer; ACol: Word; ATargetType: SmallInt; ABuffer: Pointer;
    ABufLen: SQLLEN; AInd: PSQLLEN): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TRowCount = function(AStmt: Pointer; out ACount: SQLLEN): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TMoreResults = function(AStmt: Pointer): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TCancel = function(AStmt: Pointer): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TFreeStmt = function(AStmt: Pointer; AOption: Word): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TGetDiagRecW = function(AType: SmallInt; AHandle: Pointer; ARec: SmallInt; AState: PWideChar;
    out ANative: LongInt; AText: PWideChar; ATextMax: SmallInt; out ATextLen: SmallInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};
  TGetDiagField = function(AType: SmallInt; AHandle: Pointer; ARec: SmallInt; AField: SmallInt;
    AInfo: Pointer; ABufLen: SmallInt; out AStrLen: SmallInt): SQLRETURN;
    {$IFDEF WINDOWS}stdcall{$ELSE}cdecl{$ENDIF};

var
  Lib: TLibHandle = NilHandle;
  Env: Pointer = nil;
  LoadLock: TCriticalSection = nil;
  SQLAllocHandle: TAllocHandle;
  SQLFreeHandle: TFreeHandle;
  SQLSetEnvAttr: TSetEnvAttr;
  SQLSetConnectAttr: TSetConnectAttr;
  SQLDriverConnectW: TDriverConnectW;
  SQLDisconnect: TDisconnect;
  SQLExecDirectW: TExecDirectW;
  SQLNumResultCols: TNumResultCols;
  SQLDescribeColW: TDescribeColW;
  SQLFetch: TFetch;
  SQLGetData: TGetData;
  SQLRowCount: TRowCount;
  SQLMoreResults: TMoreResults;
  SQLCancel: TCancel;
  SQLFreeStmt: TFreeStmt;
  SQLGetDiagRecW: TGetDiagRecW;
  SQLGetDiagField: TGetDiagField;

function Succeeded(ARet: SQLRETURN): Boolean;
begin
  Result := (ARet = SQL_SUCCESS) or (ARet = SQL_SUCCESS_WITH_INFO);
end;

procedure LoadOdbc;
var
  Names: array of string;
  I: Integer;

  function Proc(const AName: string): Pointer;
  begin
    Result := GetProcedureAddress(Lib, AName);
    if Result = nil then
    begin
      raise Exception.Create('The ODBC driver manager has no ' + AName + '.');
    end;
  end;

begin
  LoadLock.Enter;
  try
    if Env <> nil then
    begin
      Exit;
    end;
    {$IFDEF WINDOWS}
    Names := ['odbc32.dll'];
    {$ELSE}
    Names := ['libodbc.so.2', 'libodbc.so', 'libiodbc.so.2'];
    {$ENDIF}
    for I := 0 to High(Names) do
    begin
      if Lib = NilHandle then
      begin
        Lib := LoadLibrary(Names[I]);
      end;
    end;
    if Lib = NilHandle then
    begin
      {$IFDEF WINDOWS}
      raise Exception.Create('Could not load odbc32.dll (the Windows ODBC driver manager).');
      {$ELSE}
      raise Exception.Create('Could not load the ODBC driver manager (libodbc.so.2). Install unixODBC ' +
        '(e.g. apt install unixodbc) and an SQL Server driver: Microsoft''s msodbcsql18, or FreeTDS ' +
        '(tdsodbc).');
      {$ENDIF}
    end;
    Pointer(SQLAllocHandle) := Proc('SQLAllocHandle');
    Pointer(SQLFreeHandle) := Proc('SQLFreeHandle');
    Pointer(SQLSetEnvAttr) := Proc('SQLSetEnvAttr');
    Pointer(SQLSetConnectAttr) := Proc('SQLSetConnectAttr');
    Pointer(SQLDriverConnectW) := Proc('SQLDriverConnectW');
    Pointer(SQLDisconnect) := Proc('SQLDisconnect');
    Pointer(SQLExecDirectW) := Proc('SQLExecDirectW');
    Pointer(SQLNumResultCols) := Proc('SQLNumResultCols');
    Pointer(SQLDescribeColW) := Proc('SQLDescribeColW');
    Pointer(SQLFetch) := Proc('SQLFetch');
    Pointer(SQLGetData) := Proc('SQLGetData');
    Pointer(SQLRowCount) := Proc('SQLRowCount');
    Pointer(SQLMoreResults) := Proc('SQLMoreResults');
    Pointer(SQLCancel) := Proc('SQLCancel');
    Pointer(SQLFreeStmt) := Proc('SQLFreeStmt');
    Pointer(SQLGetDiagRecW) := Proc('SQLGetDiagRecW');
    Pointer(SQLGetDiagField) := Proc('SQLGetDiagField');
    if not Succeeded(SQLAllocHandle(SQL_HANDLE_ENV, nil, Env)) then
    begin
      Env := nil;
      raise Exception.Create('ODBC would not start (no environment handle).');
    end;
    SQLSetEnvAttr(Env, SQL_ATTR_ODBC_VERSION, Pointer(PtrInt(SQL_OV_ODBC3)), 0);
  finally
    LoadLock.Leave;
  end;
end;

{ "[Microsoft][ODBC Driver 18 for SQL Server][SQL Server]Invalid object
  name 'x'." -> "Invalid object name 'x'." }
function StripPrefixes(const AText: string): string;
begin
  Result := AText;
  while (Result <> '') and (Result[1] = '[') and (Pos(']', Result) > 0) do
  begin
    Result := Copy(Result, Pos(']', Result) + 1, MaxInt);
  end;
end;

type
  TDiag = record
    State: string;
    Native: Integer;
    Severity: Integer;
    MsgState: Integer;
    Line: Integer;
    Text: string;
  end;
  TDiags = array of TDiag;

function ReadDiags(AType: SmallInt; AHandle: Pointer): TDiags;
var
  Rec: SmallInt;
  State: array[0..7] of WideChar;
  Text: array[0..4095] of WideChar;
  Native: LongInt;
  Len, SLen: SmallInt;
  Buf: Int64;
  D: TDiag;
begin
  Result := nil;
  Rec := 1;
  while Rec < 200 do
  begin
    FillChar(State, SizeOf(State), 0);
    FillChar(Text, SizeOf(Text), 0);
    Native := 0;
    Len := 0;
    if not Succeeded(SQLGetDiagRecW(AType, AHandle, Rec, @State[0], Native, @Text[0], Length(Text) - 1,
      Len)) then
    begin
      Break;
    end;
    D.State := UTF8Encode(WideString(PWideChar(@State[0])));
    D.Native := Native;
    D.Text := StripPrefixes(UTF8Encode(WideString(PWideChar(@Text[0]))));
    D.Severity := -1;
    D.MsgState := -1;
    D.Line := -1;
    Buf := 0;
    if Succeeded(SQLGetDiagField(AType, AHandle, Rec, SQL_DIAG_SS_SEVERITY, @Buf, SizeOf(Buf), SLen)) then
    begin
      D.Severity := LongInt(Buf and $FFFFFFFF);
    end;
    Buf := 0;
    if Succeeded(SQLGetDiagField(AType, AHandle, Rec, SQL_DIAG_SS_MSGSTATE, @Buf, SizeOf(Buf), SLen)) then
    begin
      D.MsgState := LongInt(Buf and $FFFFFFFF);
    end;
    Buf := 0;
    if Succeeded(SQLGetDiagField(AType, AHandle, Rec, SQL_DIAG_SS_LINE, @Buf, SizeOf(Buf), SLen)) then
    begin
      D.Line := Word(Buf and $FFFF);
    end;
    SetLength(Result, Length(Result) + 1);
    Result[High(Result)] := D;
    Inc(Rec);
  end;
end;

function Max0(AValue: Integer): Integer;
begin
  if AValue < 0 then
  begin
    Result := 0;
  end
  else
  begin
    Result := AValue;
  end;
end;

{ As SSMS writes them: "Msg 208, Level 16, State 1, Line 3" then the text. }
function DiagText(const D: TDiag): string;
begin
  if (D.Native > 0) and (D.Severity >= 0) then
  begin
    Result := Format('Msg %d, Level %d, State %d', [D.Native, D.Severity, Max0(D.MsgState)]);
    if D.Line > 0 then
    begin
      Result := Result + ', Line ' + IntToStr(D.Line);
    end;
    Result := Result + LineEnding + D.Text;
  end
  else if D.Native > 0 then
  begin
    Result := 'Msg ' + IntToStr(D.Native) + ': ' + D.Text;
  end
  else
  begin
    Result := D.Text;
  end;
end;

{ ------------------------------------------------------------ connection }

constructor TpgnOdbcConnection.Create;
begin
  inherited Create;
  FLock := TCriticalSection.Create;
end;

destructor TpgnOdbcConnection.Destroy;
begin
  Disconnect;
  FLock.Free;
  inherited Destroy;
end;

procedure TpgnOdbcConnection.Check(ARet: SmallInt; AHandleType: SmallInt; AHandle: Pointer;
  const AWhat: string);
var
  D: TDiags;
  I: Integer;
  Msg: string;
  E: EpgnOdbcError;
begin
  if Succeeded(ARet) or (ARet = SQL_NO_DATA) then
  begin
    Exit;
  end;
  D := ReadDiags(AHandleType, AHandle);
  Msg := '';
  for I := 0 to High(D) do
  begin
    if Msg <> '' then
    begin
      Msg := Msg + LineEnding;
    end;
    Msg := Msg + DiagText(D[I]);
  end;
  if Msg = '' then
  begin
    Msg := AWhat + ' failed (ODBC code ' + IntToStr(ARet) + ').';
  end;
  E := EpgnOdbcError.Create(Msg);
  if Length(D) > 0 then
  begin
    E.SqlState := D[0].State;
    E.NativeError := D[0].Native;
  end;
  raise E;
end;

procedure TpgnOdbcConnection.Connect(const AConnStr: string);
var
  W: UnicodeString;
  OutBuf: array[0..1023] of WideChar;
  OutLen: SmallInt;
  Ret: SQLRETURN;
begin
  LoadOdbc;
  Disconnect;
  if not Succeeded(SQLAllocHandle(SQL_HANDLE_DBC, Env, FDbc)) then
  begin
    FDbc := nil;
    raise Exception.Create('ODBC would not make a connection handle.');
  end;
  SQLSetConnectAttr(FDbc, SQL_ATTR_LOGIN_TIMEOUT, Pointer(PtrInt(15)), 0);
  W := UTF8Decode(AConnStr);
  OutLen := 0;
  Ret := SQLDriverConnectW(FDbc, nil, PWideChar(W), SQL_NTS, @OutBuf[0], Length(OutBuf) - 1, OutLen,
    SQL_DRIVER_NOPROMPT);
  try
    Check(Ret, SQL_HANDLE_DBC, FDbc, 'Connecting');
  except
    SQLFreeHandle(SQL_HANDLE_DBC, FDbc);
    FDbc := nil;
    raise;
  end;
end;

procedure TpgnOdbcConnection.Disconnect;
begin
  if FDbc <> nil then
  begin
    SQLDisconnect(FDbc);
    SQLFreeHandle(SQL_HANDLE_DBC, FDbc);
    FDbc := nil;
  end;
end;

function TpgnOdbcConnection.Connected: Boolean;
begin
  Result := FDbc <> nil;
end;

procedure TpgnOdbcConnection.Cancel;
begin
  FLock.Enter;
  try
    if FStmt <> nil then
    begin
      SQLCancel(FStmt);
    end;
  finally
    FLock.Leave;
  end;
end;

function TpgnOdbcConnection.Run(const ASQL: string; ARowLimit: Integer): TpgnResultSet;
var
  Stmt: Pointer;
  W: UnicodeString;
  Ret: SQLRETURN;
  Last, Cur: TpgnResultSet;
  Messages: TStringList;
  GotRows: Boolean;
  Affected: Int64;
  I: Integer;

  procedure TakeInfo;
  var
    D: TDiags;
    J: Integer;
  begin
    D := ReadDiags(SQL_HANDLE_STMT, Stmt);
    for J := 0 to High(D) do
    begin
      if D[J].State <> '01004' then   // not "string data, right truncation"
      begin
        Messages.Add(DiagText(D[J]));
      end;
    end;
  end;

  procedure Fail(ARet: SQLRETURN; const AWhat: string);
  var
    D: TDiags;
    J: Integer;
    Msg: string;
    E: EpgnOdbcError;
  begin
    D := ReadDiags(SQL_HANDLE_STMT, Stmt);
    Msg := '';
    // messages that came before the error first (PRINT ...), then the error
    for J := 0 to Messages.Count - 1 do
    begin
      Msg := Msg + Messages[J] + LineEnding;
    end;
    for J := 0 to High(D) do
    begin
      Msg := Msg + DiagText(D[J]);
      if J < High(D) then
      begin
        Msg := Msg + LineEnding;
      end;
    end;
    if Trim(Msg) = '' then
    begin
      Msg := AWhat + ' failed (ODBC code ' + IntToStr(ARet) + ').';
    end;
    E := EpgnOdbcError.Create(TrimRight(Msg));
    if Length(D) > 0 then
    begin
      E.SqlState := D[0].State;
      E.NativeError := D[0].Native;
    end;
    raise E;
  end;

  { the column's value as text; binary values as "(binary, n bytes)" }
  function ColumnText(ACol: Word; AType: SmallInt; out AIsNull: Boolean): string;
  var
    WBuf: array[0..4095] of WideChar;
    BBuf: array[0..8191] of Byte;
    Ind: SQLLEN;
    R: SQLRETURN;
    Part: UnicodeString;
    Total: Int64;
    Chars: Integer;
  begin
    Result := '';
    AIsNull := False;
    if (AType = SQL_BINARY) or (AType = SQL_VARBINARY) or (AType = SQL_LONGVARBINARY) or (AType = SQL_SS_UDT) then
    begin
      Total := 0;
      repeat
        Ind := 0;
        R := SQLGetData(Stmt, ACol, SQL_C_BINARY, @BBuf[0], SizeOf(BBuf), @Ind);
        if R = SQL_NO_DATA then
        begin
          Break;
        end;
        if not Succeeded(R) then
        begin
          Fail(R, 'Reading a value');
        end;
        if Ind = SQL_NULL_DATA then
        begin
          AIsNull := True;
          Exit;
        end;
        if (Ind = SQL_NO_TOTAL) or (Ind > SizeOf(BBuf)) then
        begin
          Total := Total + SizeOf(BBuf);
        end
        else
        begin
          Total := Total + Ind;
        end;
      until R = SQL_SUCCESS;
      Result := Format('(binary, %d bytes)', [Total]);
      Exit;
    end;
    Part := '';
    repeat
      Ind := 0;
      FillChar(WBuf, 2, 0);
      R := SQLGetData(Stmt, ACol, SQL_C_WCHAR, @WBuf[0], SizeOf(WBuf), @Ind);
      if R = SQL_NO_DATA then
      begin
        Break;
      end;
      if not Succeeded(R) then
      begin
        Fail(R, 'Reading a value');
      end;
      if Ind = SQL_NULL_DATA then
      begin
        AIsNull := True;
        Exit;
      end;
      if (R = SQL_SUCCESS_WITH_INFO) and ((Ind = SQL_NO_TOTAL) or (Ind >= SizeOf(WBuf))) then
      begin
        // more to come: the buffer is full, less its terminator
        Chars := Length(WBuf) - 1;
      end
      else
      begin
        Chars := Ind div SizeOf(WideChar);
      end;
      SetLength(Part, Length(Part) + Chars);
      if Chars > 0 then
      begin
        Move(WBuf[0], Part[Length(Part) - Chars + 1], Chars * SizeOf(WideChar));
      end;
    until R = SQL_SUCCESS;
    Result := UTF8Encode(Part);
  end;

  procedure ReadRows(AInto: TpgnResultSet; ACols: SmallInt);
  var
    C, Count, Cap: Integer;
    NameBuf: array[0..255] of WideChar;
    NameLen, DigitsDummy, NullDummy: SmallInt;
    Types: array of SmallInt;
    Size: SQLULEN;
    R: SQLRETURN;
    IsNull: Boolean;
  begin
    SetLength(AInto.Columns, ACols);
    SetLength(Types, ACols);
    for C := 0 to ACols - 1 do
    begin
      FillChar(NameBuf, SizeOf(NameBuf), 0);
      NameLen := 0;
      SQLDescribeColW(Stmt, C + 1, @NameBuf[0], Length(NameBuf) - 1, NameLen, Types[C], Size,
        DigitsDummy, NullDummy);
      AInto.Columns[C] := UTF8Encode(WideString(PWideChar(@NameBuf[0])));
      if AInto.Columns[C] = '' then
      begin
        AInto.Columns[C] := '(No column name)';   // as SSMS shows it
      end;
    end;
    Count := 0;
    Cap := 0;
    AInto.Rows := nil;
    while (ARowLimit <= 0) or (Count < ARowLimit) do
    begin
      R := SQLFetch(Stmt);
      if R = SQL_NO_DATA then
      begin
        Break;
      end;
      if not Succeeded(R) then
      begin
        Fail(R, 'Fetching rows');
      end;
      if Count >= Cap then
      begin
        if Cap = 0 then
        begin
          Cap := 256;
        end
        else
        begin
          Cap := Cap * 2;
        end;
        SetLength(AInto.Rows, Cap);
      end;
      SetLength(AInto.Rows[Count].Values, ACols);
      SetLength(AInto.Rows[Count].Nulls, ACols);
      for C := 0 to ACols - 1 do
      begin
        AInto.Rows[Count].Values[C] := ColumnText(C + 1, Types[C], IsNull);
        AInto.Rows[Count].Nulls[C] := IsNull;
      end;
      Inc(Count);
    end;
    SetLength(AInto.Rows, Count);
    AInto.HasMoreRows := False;
    if (ARowLimit > 0) and (Count >= ARowLimit) then
    begin
      R := SQLFetch(Stmt);
      AInto.HasMoreRows := Succeeded(R);
    end;
    AInto.ReturnsRows := True;
  end;

  procedure ReadCurrent;
  var
    Cols: SmallInt;
    Rc: SQLLEN;
  begin
    Cols := 0;
    SQLNumResultCols(Stmt, Cols);
    if Cols > 0 then
    begin
      if not GotRows then
      begin
        Cur := Result;
        GotRows := True;
      end
      else
      begin
        Cur := TpgnResultSet.Create;
        Last.Next := Cur;
      end;
      ReadRows(Cur, Cols);
      Last := Cur;
      if Cur.HasMoreRows then
      begin
        Messages.Add(Format('(first %d rows)', [Cur.RowCount]));
      end
      else if Cur.RowCount = 1 then
      begin
        Messages.Add('(1 row affected)');
      end
      else
      begin
        Messages.Add(Format('(%d rows affected)', [Cur.RowCount]));
      end;
    end
    else
    begin
      Rc := -1;
      if Succeeded(SQLRowCount(Stmt, Rc)) and (Rc >= 0) then
      begin
        Affected := Affected + Rc;
        if Rc = 1 then
        begin
          Messages.Add('(1 row affected)');
        end
        else
        begin
          Messages.Add(Format('(%d rows affected)', [Int64(Rc)]));
        end;
      end;
    end;
  end;

begin
  if FDbc = nil then
  begin
    raise Exception.Create('Not connected.');
  end;
  if not Succeeded(SQLAllocHandle(SQL_HANDLE_STMT, FDbc, Stmt)) then
  begin
    Check(SQL_ERROR, SQL_HANDLE_DBC, FDbc, 'Making a statement');
  end;
  FLock.Enter;
  FStmt := Stmt;
  FLock.Leave;
  Messages := TStringList.Create;
  Result := TpgnResultSet.Create;
  Last := nil;
  GotRows := False;
  Affected := 0;
  try
    try
      W := UTF8Decode(ASQL);
      Ret := SQLExecDirectW(Stmt, PWideChar(W), SQL_NTS);
      if (Ret = SQL_ERROR) or (Ret = SQL_INVALID_HANDLE) then
      begin
        Fail(Ret, 'Running the statement');
      end;
      while True do
      begin
        if Ret = SQL_SUCCESS_WITH_INFO then
        begin
          TakeInfo;
        end;
        // (an UPDATE that touched no rows says SQL_NO_DATA: still "(0 rows affected)")
        ReadCurrent;
        Ret := SQLMoreResults(Stmt);
        if Ret = SQL_NO_DATA then
        begin
          Break;
        end;
        if (Ret = SQL_ERROR) or (Ret = SQL_INVALID_HANDLE) then
        begin
          Fail(Ret, 'Running the statement');
        end;
      end;
      if not GotRows then
      begin
        Result.ReturnsRows := False;
        Result.RowsAffected := Affected;
      end;
      SetLength(Result.Messages, Messages.Count);
      for I := 0 to Messages.Count - 1 do
      begin
        Result.Messages[I] := Messages[I];
      end;
    except
      FreeAndNil(Result);
      raise;
    end;
  finally
    FLock.Enter;
    FStmt := nil;
    FLock.Leave;
    SQLFreeStmt(Stmt, SQL_CLOSE);
    SQLFreeHandle(SQL_HANDLE_STMT, Stmt);
    Messages.Free;
  end;
end;

initialization
  LoadLock := TCriticalSection.Create;

finalization
  if Env <> nil then
  begin
    SQLFreeHandle(SQL_HANDLE_ENV, Env);
    Env := nil;
  end;
  if Lib <> NilHandle then
  begin
    UnloadLibrary(Lib);
  end;
  FreeAndNil(LoadLock);

end.
