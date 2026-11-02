// Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
// Copyright (C) 2026 Randy Morrow
// SPDX-License-Identifier: GPL-3.0-or-later
//
// This program is free software: you can redistribute it and/or modify it
// under the terms of the GNU General Public License as published by the Free
// Software Foundation, either version 3 of the License, or (at your option)
// any later version. It is distributed WITHOUT ANY WARRANTY; see the file
// LICENSE for details.

unit pgnKeymap;

{ Keyboard profiles, named after the layouts they come with. Each profile
  maps Pagona's actions (by name) to one or more shortcuts; the first is
  the primary shortcut shown in menus.

    Pagona     F5 runs the statement under the cursor (or the selection),
               Shift+F5 runs the whole editor as a script, Ctrl+/ toggles
               comments.
    Amphibian  Toad's keys: F9 statement, F5 script, F4 describe, F8
               history, Ctrl+E explain, Ctrl+B / Ctrl+Shift+B comment.
    Seattle    SSMS's keys: F5 / Ctrl+E run the selection or the whole
               editor, Ctrl+L explain, Alt+F1 describe, and the two-key
               Ctrl+K Ctrl+C / Ctrl+K Ctrl+U for comments (handled by the
               main window, since menu shortcuts are single keys).

  The keymap setting is either one of these names or "Match layout", in
  which case it follows the chosen layout. }

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, ActnList, Menus, LCLType, LCLProc;

const
  actRunStatement = 'actRunStatement';
  actRunScript    = 'actRunScript';
  actCancel       = 'actCancel';
  actDescribe     = 'actDescribe';
  actHistory      = 'actHistory';
  actExplain      = 'actExplain';
  actComment      = 'actComment';
  actUncomment    = 'actUncomment';
  actToggleComment = 'actToggleComment';
  actBlockComment = 'actBlockComment';
  actNewTab       = 'actNewTab';
  actCloseTab     = 'actCloseTab';
  actNextTab      = 'actNextTab';
  actPrevTab      = 'actPrevTab';
  actOpenFile     = 'actOpenFile';
  actSaveFile     = 'actSaveFile';
  actSaveFileAs   = 'actSaveFileAs';
  actFind         = 'actFind';
  actFindNext     = 'actFindNext';
  actReplace      = 'actReplace';
  actResultsGrid  = 'actResultsGrid';
  actResultsText  = 'actResultsText';
  actResultsFile  = 'actResultsFile';

  KeymapMatchLayout = 'Match layout';
  KeymapPagona      = 'Pagona';
  KeymapAmphibian   = 'Amphibian';
  KeymapSeattle     = 'Seattle';

  KeymapNames: array[0..2] of string = (KeymapPagona, KeymapAmphibian, KeymapSeattle);

  LayoutPlume     = 'Plume';
  LayoutAmphibian = 'Amphibian';
  LayoutSeattle   = 'Seattle';

procedure ApplyKeymap(AActions: TActionList; const AProfile: string);

{ The keymap actually in use for a keymap setting and a layout. }
function EffectiveKeymap(const AKeymapSetting, ALayout: string): string;

{ Older settings files: "Default" and "Toad" become today's names. }
function NormalizeKeymapSetting(const AValue: string): string;

implementation

procedure Bind(AActions: TActionList; const AName: string; const AKeys: array of TShortCut);
var
  I, K: Integer;
  A: TCustomAction;
begin
  for I := 0 to AActions.ActionCount - 1 do
  begin
    if SameText(AActions.Actions[I].Name, AName) and (AActions.Actions[I] is TCustomAction) then
    begin
      A := TCustomAction(AActions.Actions[I]);
      if Length(AKeys) > 0 then
      begin
        A.ShortCut := AKeys[0];
      end;
      for K := 1 to High(AKeys) do
      begin
        A.SecondaryShortCuts.Add(ShortCutToText(AKeys[K]));
      end;
      Exit;
    end;
  end;
end;

procedure ClearAll(AActions: TActionList);
var
  I: Integer;
  A: TCustomAction;
begin
  for I := 0 to AActions.ActionCount - 1 do
  begin
    if AActions.Actions[I] is TCustomAction then
    begin
      A := TCustomAction(AActions.Actions[I]);
      A.ShortCut := 0;
      A.SecondaryShortCuts.Clear;
    end;
  end;
end;

procedure ApplyPagona(AActions: TActionList);
begin
  Bind(AActions, actRunStatement, [ShortCut(VK_F5, []), ShortCut(VK_RETURN, [ssCtrl])]);
  Bind(AActions, actRunScript,    [ShortCut(VK_F5, [ssShift]), ShortCut(VK_RETURN, [ssCtrl, ssShift])]);
  Bind(AActions, actDescribe,     [ShortCut(VK_F1, [ssAlt])]);
  Bind(AActions, actHistory,      [ShortCut(VK_H, [ssCtrl])]);
  Bind(AActions, actToggleComment, [ShortCut(VK_OEM_2, [ssCtrl])]);            // Ctrl+/
  Bind(AActions, actBlockComment, [ShortCut(VK_OEM_2, [ssCtrl, ssShift])]);    // Ctrl+Shift+/
  Bind(AActions, actReplace,      [ShortCut(VK_R, [ssCtrl])]);
end;

procedure ApplyAmphibian(AActions: TActionList);
begin
  Bind(AActions, actRunStatement, [ShortCut(VK_F9, []), ShortCut(VK_RETURN, [ssCtrl])]);
  Bind(AActions, actRunScript,    [ShortCut(VK_F5, [])]);
  Bind(AActions, actDescribe,     [ShortCut(VK_F4, [])]);
  Bind(AActions, actHistory,      [ShortCut(VK_F8, [])]);
  Bind(AActions, actExplain,      [ShortCut(VK_E, [ssCtrl])]);
  Bind(AActions, actComment,      [ShortCut(VK_B, [ssCtrl])]);
  Bind(AActions, actUncomment,    [ShortCut(VK_B, [ssCtrl, ssShift])]);
  Bind(AActions, actReplace,      [ShortCut(VK_R, [ssCtrl])]);
end;

procedure ApplySeattle(AActions: TActionList);
begin
  // SSMS runs the selection, or the whole editor when nothing is selected
  Bind(AActions, actRunScript,    [ShortCut(VK_F5, []), ShortCut(VK_E, [ssCtrl])]);
  Bind(AActions, actExplain,      [ShortCut(VK_L, [ssCtrl])]);
  Bind(AActions, actDescribe,     [ShortCut(VK_F1, [ssAlt])]);
  Bind(AActions, actReplace,      [ShortCut(VK_H, [ssCtrl])]);
  Bind(AActions, actCancel,       [ShortCut(VK_PAUSE, [ssAlt]), ShortCut(VK_CANCEL, [ssAlt])]);
  // comments: Ctrl+K Ctrl+C / Ctrl+K Ctrl+U, see the main window
end;

{ SSMS's own keys for the window commands (after the common ones). }
procedure ApplySeattleWindow(AActions: TActionList);
var
  I: Integer;
begin
  for I := 0 to AActions.ActionCount - 1 do
  begin
    if (AActions.Actions[I] is TCustomAction) and
      (SameText(AActions.Actions[I].Name, actNewTab) or SameText(AActions.Actions[I].Name, actCloseTab)) then
    begin
      TCustomAction(AActions.Actions[I]).SecondaryShortCuts.Clear;
    end;
  end;
  // Ctrl+T is Results to Text in SSMS, so a new tab is Ctrl+N only
  Bind(AActions, actNewTab,   [ShortCut(VK_N, [ssCtrl])]);
  Bind(AActions, actCloseTab, [ShortCut(VK_F4, [ssCtrl]), ShortCut(VK_W, [ssCtrl])]);
  Bind(AActions, actResultsGrid, [ShortCut(VK_D, [ssCtrl])]);
  Bind(AActions, actResultsText, [ShortCut(VK_T, [ssCtrl])]);
  Bind(AActions, actResultsFile, [ShortCut(VK_F, [ssCtrl, ssShift])]);
end;

{ Tab and file keys are the same in every profile. }
procedure ApplyCommon(AActions: TActionList);
begin
  Bind(AActions, actNewTab,   [ShortCut(VK_T, [ssCtrl])]);
  Bind(AActions, actCloseTab, [ShortCut(VK_W, [ssCtrl])]);
  // Ctrl+PageDown / PageUp too: the Linux and browser convention, and some
  // Linux tab controls keep Ctrl+Tab for themselves
  Bind(AActions, actNextTab,  [ShortCut(VK_TAB, [ssCtrl]), ShortCut(VK_NEXT, [ssCtrl])]);
  Bind(AActions, actPrevTab,  [ShortCut(VK_TAB, [ssCtrl, ssShift]), ShortCut(VK_PRIOR, [ssCtrl])]);
  Bind(AActions, actOpenFile, [ShortCut(VK_O, [ssCtrl])]);
  Bind(AActions, actSaveFile, [ShortCut(VK_S, [ssCtrl])]);
  Bind(AActions, actSaveFileAs, [ShortCut(VK_S, [ssCtrl, ssShift])]);
  Bind(AActions, actFind,     [ShortCut(VK_F, [ssCtrl])]);
  Bind(AActions, actFindNext, [ShortCut(VK_F3, [])]);
end;

procedure ApplyKeymap(AActions: TActionList; const AProfile: string);
begin
  ClearAll(AActions);
  ApplyCommon(AActions);
  if SameText(AProfile, KeymapAmphibian) then
  begin
    ApplyAmphibian(AActions);
  end
  else if SameText(AProfile, KeymapSeattle) then
  begin
    ApplySeattle(AActions);
    ApplySeattleWindow(AActions);
  end
  else
  begin
    ApplyPagona(AActions);
  end;
end;

function EffectiveKeymap(const AKeymapSetting, ALayout: string): string;
begin
  if not SameText(AKeymapSetting, KeymapMatchLayout) then
  begin
    Result := AKeymapSetting;
    Exit;
  end;
  if SameText(ALayout, LayoutAmphibian) then
  begin
    Result := KeymapAmphibian;
  end
  else if SameText(ALayout, LayoutSeattle) then
  begin
    Result := KeymapSeattle;
  end
  else
  begin
    Result := KeymapPagona;
  end;
end;

function NormalizeKeymapSetting(const AValue: string): string;
begin
  if SameText(AValue, 'Default') or (AValue = '') then
  begin
    Result := KeymapMatchLayout;
  end
  else if SameText(AValue, 'Toad') then
  begin
    Result := KeymapAmphibian;
  end
  else
  begin
    Result := AValue;
  end;
end;

end.
