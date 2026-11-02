// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnRoutineDlg;

{ Small forms for code objects, built in code:

    NewRoutineDialog   name, parameters (and return type) -> a CREATE skeleton
    ExecuteDialog      values for a routine's parameters  -> CALL / SELECT
    GrantDialog        who and which rights               -> GRANT

  Each returns SQL; the caller puts it in a tab (and runs it where that's
  the point), so what happens is always visible. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, StdCtrls, ExtCtrls, Grids, Dialogs,
  pgnTypes, pgnAdapter, pgnTheme;

{ AKind rkProcedure or rkFunction. False if canceled. }
function NewRoutineDialog(AOwner: TComponent; AAdapter: TpgnAdapter; AKind: TpgnRoutineKind;
  out ASQL: string; const ADefaultReturns: string = 'INT'): Boolean;

{ AParams as DescribeParameters returns them (Mode, Parameter, Type). }
function ExecuteDialog(AOwner: TComponent; AAdapter: TpgnAdapter; const ADatabase, AName: string;
  AKind: TpgnRoutineKind; AParams: TpgnResultSet; out ASQL: string): Boolean;

{ AObjectWord: TABLE, VIEW, PROCEDURE or FUNCTION. }
function GrantDialog(AOwner: TComponent; AAdapter: TpgnAdapter; const ADatabase, AName,
  AObjectWord: string; out ASQL: string): Boolean;

implementation

function NewForm(AOwner: TComponent; const ACaption: string; AWidth: Integer): TForm;
begin
  Result := TForm.CreateNew(AOwner);
  SmoothFont(Result.Font);
  Result.Caption := ACaption;
  Result.BorderStyle := bsDialog;
  Result.Position := poOwnerFormCenter;
  Result.ClientWidth := AWidth;
end;

function AddLabel(F: TForm; const ACaption: string; X, Y: Integer): TLabel;
begin
  Result := TLabel.Create(F);
  Result.Parent := F;
  Result.Caption := ACaption;
  Result.Left := X;
  Result.Top := Y;
end;

function AddEdit(F: TForm; X, Y, W: Integer): TEdit;
begin
  Result := TEdit.Create(F);
  Result.Parent := F;
  Result.Left := X;
  Result.Top := Y;
  Result.Width := W;
end;

{ OK and Cancel at the bottom right; each button as wide as its caption
  needs (never narrower than 90). Returns the bottom of the buttons. }
function AddButtons(F: TForm; Y: Integer; const AOkCaption: string): Integer;
var
  BOK, BCancel: TButton;

  // as wide as the caption needs, never narrower than 90 (measured on a
  // bitmap: the form has no canvas of its own until it is shown)
  function WidthFor(const ACaption: string): Integer;
  var
    B: TBitmap;
  begin
    B := TBitmap.Create;
    try
      B.Canvas.Font.Assign(F.Font);
      Result := B.Canvas.TextWidth(ACaption) + F.Scale96ToScreen(32);
    finally
      B.Free;
    end;
    if Result < F.Scale96ToScreen(90) then
    begin
      Result := F.Scale96ToScreen(90);
    end;
  end;

begin
  BCancel := TButton.Create(F);
  BCancel.Parent := F;
  BCancel.Caption := 'Cancel';
  BCancel.ModalResult := mrCancel;
  BCancel.Cancel := True;
  BCancel.Width := WidthFor(BCancel.Caption);
  BCancel.Top := Y;

  BOK := TButton.Create(F);
  BOK.Parent := F;
  BOK.Caption := AOkCaption;
  BOK.ModalResult := mrOK;
  BOK.Default := True;
  BOK.Width := WidthFor(AOkCaption);
  BOK.Top := Y;

  BCancel.Left := F.ClientWidth - BCancel.Width - 12;
  BOK.Left := BCancel.Left - BOK.Width - 8;
  Result := Y + BOK.Height;
end;

function IsNumericType(const AType: string): Boolean;
var
  T: string;
begin
  T := LowerCase(AType);
  Result := (Pos('int', T) = 1) or (Pos('tinyint', T) = 1) or (Pos('smallint', T) = 1) or
    (Pos('mediumint', T) = 1) or (Pos('bigint', T) = 1) or (Pos('decimal', T) = 1) or
    (Pos('numeric', T) = 1) or (Pos('float', T) = 1) or (Pos('double', T) = 1) or
    (Pos('real', T) = 1) or (Pos('bit', T) = 1) or (Pos('bool', T) = 1);
end;

function IsNumberText(const S: string): Boolean;
var
  D: Double;
  Fs: TFormatSettings;
begin
  Fs := DefaultFormatSettings;
  Fs.DecimalSeparator := '.';
  Result := (Trim(S) <> '') and TryStrToFloat(Trim(S), D, Fs);
end;

{ ------------------------------------------------------------- new }

const
  ParamRows = 8;   // parameter rows on the New form; more can be typed later

function NewRoutineDialog(AOwner: TComponent; AAdapter: TpgnAdapter; AKind: TpgnRoutineKind;
  out ASQL: string; const ADefaultReturns: string): Boolean;
var
  F: TForm;
  EName, EReturns: TEdit;
  PNames, PTypes: array[0..ParamRows - 1] of TEdit;
  PModes: array[0..ParamRows - 1] of TComboBox;
  Y, R, Filled, X: Integer;
  Nm, Ty: string;
  Defs: TpgnParamDefs;
begin
  Result := False;
  ASQL := '';
  F := NewForm(AOwner, 'New ' + RoutineCaption[AKind], 520);
  try
    Y := 12;
    AddLabel(F, 'Name', 16, Y);
    EName := AddEdit(F, 16, Y + 18, 300);
    Inc(Y, 54);

    // one row of plain fields per parameter (a grid's in-place editor
    // misbehaves on some widget sets)
    AddLabel(F, 'Parameters (leave rows empty if there are none)', 16, Y);
    Inc(Y, 20);
    X := 16;
    AddLabel(F, 'Name', X, Y);
    if AKind = rkProcedure then
    begin
      AddLabel(F, 'Direction', X + 196, Y);
      AddLabel(F, 'Type', X + 302, Y);
    end
    else
    begin
      AddLabel(F, 'Type', X + 196, Y);
    end;
    Inc(Y, 18);
    for R := 0 to ParamRows - 1 do
    begin
      PNames[R] := AddEdit(F, X, Y, 188);
      PModes[R] := nil;
      if AKind = rkProcedure then
      begin
        PModes[R] := TComboBox.Create(F);
        PModes[R].Parent := F;
        PModes[R].Style := csDropDownList;
        PModes[R].Items.Add('IN');
        PModes[R].Items.Add('OUT');
        PModes[R].Items.Add('INOUT');
        PModes[R].ItemIndex := 0;
        PModes[R].SetBounds(X + 196, Y, 98, PNames[R].Height);
        PTypes[R] := AddEdit(F, X + 302, Y, 180);
      end
      else
      begin
        PTypes[R] := AddEdit(F, X + 196, Y, 180);
      end;
      Inc(Y, F.Scale96ToScreen(34));   // room for the tallest field (GTK3 edits are 33)
    end;
    Inc(Y, 10);

    EReturns := nil;
    if AKind = rkFunction then
    begin
      AddLabel(F, 'Returns (type)', 16, Y);
      EReturns := AddEdit(F, 16, Y + 18, 200);
      EReturns.Text := ADefaultReturns;
      Inc(Y, 54);
    end;

    F.ClientHeight := AddButtons(F, Y, 'Start Editing') + 14;
    F.ActiveControl := EName;

    while True do
    begin
      if F.ShowModal <> mrOK then
      begin
        Exit;
      end;
      if Trim(EName.Text) <> '' then
      begin
        Break;
      end;
      MessageDlg('Give it a name first.', mtInformation, [mbOK], 0);
    end;

    Defs := nil;
    for R := 0 to ParamRows - 1 do
    begin
      Nm := Trim(PNames[R].Text);
      if Nm = '' then
      begin
        Continue;
      end;
      Ty := Trim(PTypes[R].Text);
      if Ty = '' then
      begin
        Ty := 'VARCHAR(100)';
      end;
      Filled := Length(Defs);
      SetLength(Defs, Filled + 1);
      Defs[Filled].Name := Nm;
      Defs[Filled].DataType := Ty;
      Defs[Filled].Mode := '';
      if PModes[R] <> nil then
      begin
        Defs[Filled].Mode := PModes[R].Text;
      end;
    end;
    if EReturns <> nil then
    begin
      Ty := Trim(EReturns.Text);
    end
    else
    begin
      Ty := '';
    end;
    ASQL := AAdapter.NewRoutineSQL(Trim(EName.Text), AKind, Defs, Ty);
    Result := True;
  finally
    F.Free;
  end;
end;

{ --------------------------------------------------------- execute }

function ExecuteDialog(AOwner: TComponent; AAdapter: TpgnAdapter; const ADatabase, AName: string;
  AKind: TpgnRoutineKind; AParams: TpgnResultSet; out ASQL: string): Boolean;
var
  F: TForm;
  Y, I, N: Integer;
  Edits: array of TEdit;
  Nulls: array of TCheckBox;
  Defs: TpgnParamDefs;
  L: TLabel;
  Shown: string;
begin
  Result := False;
  ASQL := '';
  N := 0;
  Defs := nil;
  if AParams <> nil then
  begin
    for I := 0 to AParams.RowCount - 1 do
    begin
      // the result type and a set-returning function's columns aren't inputs
      if (AParams.Rows[I].Values[0] = 'RETURNS') or (AParams.Rows[I].Values[0] = 'TABLE') then
      begin
        Continue;
      end;
      SetLength(Defs, N + 1);
      Defs[N].Mode := UpperCase(AParams.Rows[I].Values[0]);
      if Defs[N].Mode = '' then
      begin
        Defs[N].Mode := 'IN';
      end;
      Defs[N].Name := AParams.Rows[I].Values[1];
      Defs[N].DataType := AParams.Rows[I].Values[2];
      Defs[N].Value := '';
      Defs[N].IsNull := False;
      Inc(N);
    end;
  end;
  SetLength(Edits, N);
  SetLength(Nulls, N);

  Shown := AName;
  F := NewForm(AOwner, 'Execute ' + Shown, 480);
  try
    Y := 12;
    if N = 0 then
    begin
      AddLabel(F, Shown + ' takes no parameters.', 16, Y);
      Inc(Y, 30);
    end;
    for I := 0 to N - 1 do
    begin
      L := AddLabel(F, Defs[I].Name + '  (' + Defs[I].DataType + ', ' + Defs[I].Mode + ')', 16, Y);
      if Defs[I].Mode = 'OUT' then
      begin
        if AAdapter.Dialect = sdMySQL then
        begin
          L.Caption := L.Caption + ': comes back as @' + Defs[I].Name;
        end
        else
        begin
          L.Caption := L.Caption + ': comes back in the results';
        end;
        Edits[I] := nil;
        Nulls[I] := nil;
        Inc(Y, 28);
        Continue;
      end;
      Edits[I] := AddEdit(F, 16, Y + 18, 300);
      Nulls[I] := TCheckBox.Create(F);
      Nulls[I].Parent := F;
      Nulls[I].Caption := 'NULL';
      Nulls[I].Left := 330;
      Nulls[I].Top := Y + 20;
      Inc(Y, 52);
    end;
    if N > 0 then
    begin
      AddLabel(F, 'Text is quoted for you; numbers are sent as typed.', 16, Y);
      Inc(Y, 26);
    end;
    F.ClientHeight := AddButtons(F, Y, 'Run') + 14;
    for I := N - 1 downto 0 do
    begin
      if Edits[I] <> nil then
      begin
        F.ActiveControl := Edits[I];
      end;
    end;
    if F.ShowModal <> mrOK then
    begin
      Exit;
    end;

    for I := 0 to N - 1 do
    begin
      if Edits[I] = nil then
      begin
        Continue;
      end;
      Defs[I].IsNull := Nulls[I].Checked;
      if Nulls[I].Checked then
      begin
        Defs[I].Value := 'NULL';
      end
      else if IsNumericType(Defs[I].DataType) and IsNumberText(Edits[I].Text) then
      begin
        Defs[I].Value := Trim(Edits[I].Text);
      end
      else
      begin
        Defs[I].Value := AAdapter.QuoteLiteral(Edits[I].Text);
      end;
    end;
    ASQL := AAdapter.ExecuteRoutineSQL(ADatabase, AName, AKind, Defs);
    Result := True;
  finally
    F.Free;
  end;
end;

{ ----------------------------------------------------------- grant }

function GrantDialog(AOwner: TComponent; AAdapter: TpgnAdapter; const ADatabase, AName,
  AObjectWord: string; out ASQL: string): Boolean;
var
  F: TForm;
  EWho: TEdit;
  Boxes: array of TCheckBox;
  Words: TpgnStringArray;
  CGrantOpt: TCheckBox;
  Y, I: Integer;
  Privs: string;
begin
  Result := False;
  ASQL := '';
  Words := AAdapter.GrantRights(AObjectWord);
  SetLength(Boxes, Length(Words));

  F := NewForm(AOwner, 'Grant Rights on ' + AName, 440);
  try
    Y := 12;
    AddLabel(F, AAdapter.GranteeHint, 16, Y);
    EWho := AddEdit(F, 16, Y + 18, 300);
    Inc(Y, 56);
    AddLabel(F, 'Rights', 16, Y);
    Inc(Y, 20);
    for I := 0 to High(Words) do
    begin
      Boxes[I] := TCheckBox.Create(F);
      Boxes[I].Parent := F;
      Boxes[I].Caption := Words[I];
      Boxes[I].Left := 24;
      Boxes[I].Top := Y;
      Boxes[I].Checked := I = 0;
      Inc(Y, 24);
    end;
    CGrantOpt := TCheckBox.Create(F);
    CGrantOpt.Parent := F;
    CGrantOpt.Caption := 'They may pass these rights on (WITH GRANT OPTION)';
    CGrantOpt.Left := 16;
    CGrantOpt.Top := Y + 6;
    Inc(Y, 40);
    AddLabel(F, 'The database decides whether your login may grant these.', 16, Y);
    Inc(Y, 26);
    F.ClientHeight := AddButtons(F, Y, 'Grant') + 14;
    F.ActiveControl := EWho;

    while True do
    begin
      if F.ShowModal <> mrOK then
      begin
        Exit;
      end;
      Privs := '';
      for I := 0 to High(Words) do
      begin
        if Boxes[I].Checked then
        begin
          if Privs <> '' then
          begin
            Privs := Privs + ', ';
          end;
          Privs := Privs + Words[I];
        end;
      end;
      if (Trim(EWho.Text) <> '') and (Privs <> '') then
      begin
        Break;
      end;
      MessageDlg('Choose who, and at least one right.', mtInformation, [mbOK], 0);
    end;

    ASQL := AAdapter.GrantSQL(ADatabase, AName, AObjectWord, EWho.Text, Privs, CGrantOpt.Checked);
    Result := True;
  finally
    F.Free;
  end;
end;

end.
