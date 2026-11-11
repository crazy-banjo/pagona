// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnConvertReport;

{ The Oracle/PostgreSQL Compatibility report: one self-contained HTML page
  (no images, scripts or other files) or CSV, one row per finding.

  What a stored function is comes only from the data dictionary: schema,
  package, parameters and their types, return type, status, last change and
  the tables it reads. Its source code is never read into the report. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, StrUtils, pgnTypes, pgnOracleConvert;

type
  TpgnReportInfo = record
    Source: string;       // 'the selection' / 'the editor' / a file name
    Connection: string;   // where functions were looked up ('' = none)
    Converted: string;    // the result, as shown
  end;

function ConvertReportHtml(AJob: TpgnConvJob; const AInfo: TpgnReportInfo): string;
function ConvertReportCsv(AJob: TpgnConvJob; const AInfo: TpgnReportInfo): string;

implementation

type
  TLineArray = array of Integer;

function Esc(const S: string): string;
begin
  Result := StringReplace(S, '&', '&amp;', [rfReplaceAll]);
  Result := StringReplace(Result, '<', '&lt;', [rfReplaceAll]);
  Result := StringReplace(Result, '>', '&gt;', [rfReplaceAll]);
  Result := StringReplace(Result, '"', '&quot;', [rfReplaceAll]);
end;

function CsvField(const S: string): string;
begin
  Result := S;
  if (Pos(',', S) > 0) or (Pos('"', S) > 0) or (Pos(#10, S) > 0) or (Pos(#13, S) > 0) then
  begin
    Result := '"' + StringReplace(S, '"', '""', [rfReplaceAll]) + '"';
  end;
end;

{ The line of each finding's TODO PG note in the converted text (0 when it
  isn't a note), in order. }
function FindingLines(AJob: TpgnConvJob; const AText: string): TLineArray;
var
  I, P, From, K, Line: Integer;
  Needle: string;
begin
  Result := nil;
  SetLength(Result, Length(AJob.Findings));
  From := 1;
  for I := 0 to High(AJob.Findings) do
  begin
    Result[I] := 0;
    if RuleInfo(AJob.Findings[I].Rule).Group <> cgFlag then
    begin
      Continue;
    end;
    Needle := TodoPG + AJob.Findings[I].Text;
    P := Pos(Needle, Copy(AText, From, MaxInt));
    if P = 0 then
    begin
      P := Pos(Needle, AText);   // out of order: search from the top
      if P = 0 then
      begin
        Continue;
      end;
    end
    else
    begin
      P := P + From - 1;
    end;
    Line := 1;
    for K := 1 to P - 1 do
    begin
      if AText[K] = #10 then
      begin
        Inc(Line);
      end;
    end;
    Result[I] := Line;
    From := P + Length(Needle);
  end;
end;

function GroupName(AGroup: TpgnConvGroup): string;
begin
  case AGroup of
    cgSame:
      begin
        Result := 'Converted';
      end;
    cgChanges:
      begin
        Result := 'Converted (could change results)';
      end;
    cgPgOnly:
      begin
        Result := 'PostgreSQL only';
      end;
  else
    begin
      Result := 'TODO PG';
    end;
  end;
end;

function ConvertReportHtml(AJob: TpgnConvJob; const AInfo: TpgnReportInfo): string;
var
  B: TStringList;
  Lines: TLineArray;
  I: Integer;
  F: TpgnConvFunc;
  Info: TpgnRuleInfo;
  LineTxt, Pkg: string;

  procedure Add(const S: string);
  begin
    B.Add(S);
  end;

  procedure Row(const ACells: array of string);
  var
    K: Integer;
    S: string;
  begin
    S := '<tr>';
    for K := Low(ACells) to High(ACells) do
    begin
      S := S + '<td>' + Esc(ACells[K]) + '</td>';
    end;
    Add(S + '</tr>');
  end;

begin
  B := TStringList.Create;
  try
    Lines := FindingLines(AJob, AInfo.Converted);
    Add('<!DOCTYPE html>');
    Add('<html lang="en"><head><meta charset="utf-8">');
    Add('<meta name="viewport" content="width=device-width, initial-scale=1">');
    Add('<title>Oracle/PostgreSQL Compatibility report</title>');
    Add('<style>');
    Add('body { font-family: "Segoe UI", Arial, sans-serif; color: #1F2328; background: #FFFFFF; margin: 24px; ' +
      'max-width: 1200px; }');
    Add('h1 { font-size: 22px; margin: 0 0 4px; } h2 { font-size: 17px; margin: 28px 0 8px; ' +
      'border-bottom: 1px solid #D0D7DE; padding-bottom: 4px; }');
    Add('p.meta { color: #57606A; margin: 2px 0; }');
    Add('table { border-collapse: collapse; width: 100%; font-size: 13px; }');
    Add('th, td { border: 1px solid #D0D7DE; padding: 4px 8px; text-align: left; vertical-align: top; }');
    Add('th { background: #F6F8FA; }');
    Add('td.num { text-align: right; white-space: nowrap; }');
    Add('pre { background: #F6F8FA; border: 1px solid #D0D7DE; padding: 10px; overflow-x: auto; ' +
      'font-size: 12px; }');
    Add('ul { margin: 4px 0; }');
    Add('@media print { body { margin: 0; } pre { white-space: pre-wrap; } }');
    Add('</style></head><body>');
    Add('<h1>Oracle/PostgreSQL Compatibility report</h1>');
    Add('<p class="meta">Made by Pagona ' + Esc(PagonaVersion) + ', ' +
      Esc(FormatDateTime('yyyy-mm-dd hh:nn', Now)) + '. Source: ' + Esc(AInfo.Source) + '.</p>');
    if AInfo.Connection <> '' then
    begin
      Add('<p class="meta">Functions looked up on: ' + Esc(AInfo.Connection) +
        ' (data dictionary only; no source code).</p>');
    end
    else
    begin
      Add('<p class="meta">No connection: functions were not looked up.</p>');
    end;
    Add('<p class="meta">Target: SQL that runs on Oracle 19c and PostgreSQL. ' + IntToStr(AJob.AppliedIn(cgSame) +
      AJob.AppliedIn(cgChanges)) + ' change(s), ' + IntToStr(AJob.AppliedIn(cgPgOnly)) +
      ' PostgreSQL only replacement(s), ' + IntToStr(AJob.AppliedIn(cgFlag)) + ' TODO PG note(s).</p>');

    Add('<h2>What was done</h2><ul>');
    for I := 0 to AJob.Notes.Count - 1 do
    begin
      Add('<li>' + Esc(AJob.Notes[I]) + '</li>');
    end;
    Add('</ul>');

    Add('<h2>TODO PG notes and PostgreSQL only replacements</h2>');
    Add('<table><tr><th>Line</th><th>Kind</th><th>Rule</th><th>Function</th><th>PostgreSQL</th></tr>');
    for I := 0 to High(AJob.Findings) do
    begin
      Info := RuleInfo(AJob.Findings[I].Rule);
      if not (Info.Group in [cgFlag, cgPgOnly]) then
      begin
        Continue;
      end;
      LineTxt := '';
      if Lines[I] > 0 then
      begin
        LineTxt := IntToStr(Lines[I]);
      end;
      Row([LineTxt, GroupName(Info.Group), Info.Caption, AJob.Findings[I].Func, AJob.Findings[I].Text]);
    end;
    Add('</table>');

    if Length(AJob.Funcs) > 0 then
    begin
      Add('<h2>Stored functions called</h2>');
      Add('<table><tr><th>Schema</th><th>Package</th><th>Name</th><th>Calls</th><th>Kind</th><th>Returns</th>' +
        '<th>Parameters</th><th>Versions</th><th>Status</th><th>Last changed</th><th>Reads</th><th>Note</th></tr>');
      for I := 0 to High(AJob.Funcs) do
      begin
        F := AJob.Funcs[I];
        if F.Info.Found then
        begin
          Pkg := F.Info.PackageName;
          Row([F.Info.Owner, Pkg, F.Info.Name, IntToStr(F.Calls), F.Info.Kind, F.Info.ReturnType, F.Info.Params,
            IntToStr(F.Info.Overloads), F.Info.Status, F.Info.LastChanged, F.Info.Reads, F.Info.Note]);
        end
        else
        begin
          Row([F.Schema, '', F.Name, IntToStr(F.Calls), '', '', '', '', '', '', '', F.Info.Note]);
        end;
      end;
      Add('</table>');
    end;

    Add('<h2>Converted SQL</h2>');
    Add('<pre>' + Esc(AInfo.Converted) + '</pre>');
    Add('</body></html>');
    Result := B.Text;
  finally
    B.Free;
  end;
end;

function ConvertReportCsv(AJob: TpgnConvJob; const AInfo: TpgnReportInfo): string;
var
  B: TStringList;
  Lines: TLineArray;
  I: Integer;
  Info: TpgnRuleInfo;
  LineTxt: string;
  F: TpgnConvFunc;
  R: TpgnConvRule;
begin
  B := TStringList.Create;
  try
    Lines := FindingLines(AJob, AInfo.Converted);
    B.Add('Line,Kind,Rule,Schema,Function,Note');
    // conversions: one row per rule, with how many
    for R := Low(TpgnConvRule) to High(TpgnConvRule) do
    begin
      Info := RuleInfo(R);
      if (AJob.Applied[R] > 0) and (Info.Group in [cgSame, cgChanges]) then
      begin
        B.Add(',' + CsvField(GroupName(Info.Group)) + ',' + CsvField(Info.Caption) + ',,,' +
          CsvField(IntToStr(AJob.Applied[R]) + ' time(s)'));
      end;
    end;
    for I := 0 to High(AJob.Findings) do
    begin
      Info := RuleInfo(AJob.Findings[I].Rule);
      if Info.Group in [cgSame, cgChanges] then
      begin
        Continue;
      end;
      LineTxt := '';
      if Lines[I] > 0 then
      begin
        LineTxt := IntToStr(Lines[I]);
      end;
      B.Add(LineTxt + ',' + CsvField(GroupName(Info.Group)) + ',' + CsvField(Info.Caption) + ',' +
        CsvField(AJob.Findings[I].Schema) + ',' + CsvField(AJob.Findings[I].Func) + ',' +
        CsvField(AJob.Findings[I].Text));
    end;
    // the functions, one row each, described from the data dictionary
    for I := 0 to High(AJob.Funcs) do
    begin
      F := AJob.Funcs[I];
      if F.Info.Found then
      begin
        B.Add(',Function,' + CsvField(F.Info.Kind) + ',' + CsvField(F.Info.Owner) + ',' + CsvField(F.Name) + ',' +
          CsvField(IntToStr(F.Calls) + ' call(s); returns ' + F.Info.ReturnType + '; parameters: ' +
          F.Info.Params + '; status ' + F.Info.Status + '; last changed ' + F.Info.LastChanged + '; reads ' +
          F.Info.Reads + IfThen(F.Info.Note <> '', '; ' + F.Info.Note, '')));
      end
      else
      begin
        B.Add(',Function,,' + CsvField(F.Schema) + ',' + CsvField(F.Name) + ',' +
          CsvField(IntToStr(F.Calls) + ' call(s)' + IfThen(F.Info.Note <> '', '; ' + F.Info.Note, '')));
      end;
    end;
    Result := B.Text;
  finally
    B.Free;
  end;
end;

end.
