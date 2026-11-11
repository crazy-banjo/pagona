; Pagona - a database client for MySQL, PostgreSQL, Oracle and SQL Server
; Copyright (C) 2026 Randy Morrow
; SPDX-License-Identifier: GPL-3.0-or-later
;
; The Windows installer (NSIS 3). Built by the release workflow:
;   makensis /DVERSION=0.1.0 installer\pagona.nsi
; or dropped on MakeNSISW (the version is then read from src\pgntypes.pas)
; from the repository's top folder, after the Release build has made
; bin\pagona.exe. Installs for all users into Program Files (needs an
; administrator). The database client libraries are optional and not
; ticked: a PC may already have the versions its other software needs.

Unicode true
SetCompressor /SOLID lzma

; No /DVERSION (dropped on MakeNSISW, say): read it from Pagona's own source,
; so the installer always matches the program. makensis works from this
; script's folder, so the path is relative to it.
!ifndef VERSION
  !searchparse /noerrors /file "..\src\pgntypes.pas" "  PagonaVersion = '" VERSION "';"
!endif
!ifndef VERSION
  !error "Couldn't read PagonaVersion from src\pgntypes.pas: build with /DVERSION=x.y.z"
!endif
!define APPNAME "Pagona"
!define PUBLISHER "Randy Morrow"
!define URL "https://github.com/crazy-banjo/pagona"
!define UNINSTKEY "Software\Microsoft\Windows\CurrentVersion\Uninstall\Pagona"
!define REDIST "..\redist\windows-x64"

!include "MUI2.nsh"
!include "x64.nsh"
!include "FileFunc.nsh"

Name "${APPNAME} ${VERSION}"
OutFile "..\dist\Pagona-${VERSION}-setup.exe"
InstallDir "$PROGRAMFILES64\Pagona"
InstallDirRegKey HKLM "Software\Pagona" "InstallDir"
RequestExecutionLevel admin
BrandingText "${APPNAME} ${VERSION}"

VIProductVersion "${VERSION}.0"
VIAddVersionKey "ProductName" "${APPNAME}"
VIAddVersionKey "ProductVersion" "${VERSION}"
VIAddVersionKey "FileVersion" "${VERSION}"
VIAddVersionKey "FileDescription" "${APPNAME} ${VERSION} setup"
VIAddVersionKey "CompanyName" "${PUBLISHER}"
VIAddVersionKey "LegalCopyright" "Copyright (C) 2026 ${PUBLISHER}. GPL-3.0-or-later."

!define MUI_ICON "..\pagona.ico"
!define MUI_UNICON "..\pagona.ico"
!define MUI_ABORTWARNING
!define MUI_COMPONENTSPAGE_SMALLDESC
!define MUI_FINISHPAGE_RUN "$INSTDIR\pagona.exe"
!define MUI_FINISHPAGE_RUN_TEXT "Start Pagona"

!insertmacro MUI_PAGE_WELCOME
!define MUI_LICENSEPAGE_TEXT_TOP "Pagona is free software under the GNU General Public License, version 3 or later."
!insertmacro MUI_PAGE_LICENSE "..\LICENSE"
!insertmacro MUI_PAGE_COMPONENTS
!insertmacro MUI_PAGE_DIRECTORY
!insertmacro MUI_PAGE_INSTFILES
!insertmacro MUI_PAGE_FINISH

!insertmacro MUI_UNPAGE_CONFIRM
!insertmacro MUI_UNPAGE_COMPONENTS
!insertmacro MUI_UNPAGE_INSTFILES

!insertmacro MUI_LANGUAGE "English"

Function .onInit
  ${IfNot} ${RunningX64}
    MessageBox MB_OK|MB_ICONSTOP "Pagona needs 64-bit Windows."
    Abort
  ${EndIf}
  SetRegView 64
FunctionEnd

Function un.onInit
  SetRegView 64
FunctionEnd

Section "Pagona (required)" SecApp
  SectionIn RO
  SetShellVarContext all
  SetOutPath "$INSTDIR"
  File "..\bin\pagona.exe"
  File "/oname=LICENSE.txt" "..\LICENSE"
  File "..\THIRD-PARTY-NOTICES.md"
  File "/oname=README.md" "..\README.md"
  WriteUninstaller "$INSTDIR\uninstall.exe"

  WriteRegStr HKLM "Software\Pagona" "InstallDir" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayName" "${APPNAME}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayVersion" "${VERSION}"
  WriteRegStr HKLM "${UNINSTKEY}" "Publisher" "${PUBLISHER}"
  WriteRegStr HKLM "${UNINSTKEY}" "URLInfoAbout" "${URL}"
  WriteRegStr HKLM "${UNINSTKEY}" "DisplayIcon" "$INSTDIR\pagona.exe"
  WriteRegStr HKLM "${UNINSTKEY}" "InstallLocation" "$INSTDIR"
  WriteRegStr HKLM "${UNINSTKEY}" "UninstallString" '"$INSTDIR\uninstall.exe"'
  WriteRegStr HKLM "${UNINSTKEY}" "QuietUninstallString" '"$INSTDIR\uninstall.exe" /S'
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoModify" 1
  WriteRegDWORD HKLM "${UNINSTKEY}" "NoRepair" 1
SectionEnd

Section "Start Menu shortcut" SecStartMenu
  SetShellVarContext all
  CreateShortcut "$SMPROGRAMS\Pagona.lnk" "$INSTDIR\pagona.exe"
SectionEnd

Section /o "Desktop shortcut" SecDesktop
  SetShellVarContext all
  CreateShortcut "$DESKTOP\Pagona.lnk" "$INSTDIR\pagona.exe"
SectionEnd

SectionGroup "Database client libraries (optional)" SecLibs
  Section /o "PostgreSQL client (libpq)" SecPg
    SetOutPath "$INSTDIR"
    File "${REDIST}\libpq.dll"
    File "${REDIST}\libintl-9.dll"
    File "${REDIST}\libiconv-2.dll"
    File "${REDIST}\libwinpthread-1.dll"
    File "${REDIST}\libssl-3-x64.dll"
    File "${REDIST}\libcrypto-3-x64.dll"
    File "${REDIST}\vcruntime140.dll"
  SectionEnd

  Section /o "MySQL client (libmysql)" SecMySql
    SetOutPath "$INSTDIR"
    File "${REDIST}\libmysql.dll"
    File "${REDIST}\libssl-3-x64.dll"
    File "${REDIST}\libcrypto-3-x64.dll"
    File "${REDIST}\vcruntime140.dll"
    ; libmysql also needs the rest of the Visual C++ runtime (64-bit, in the
    ; real System32: the installer is 32-bit, so look past the redirection)
    ${DisableX64FSRedirection}
    StrCpy $0 "ok"
    ${IfNot} ${FileExists} "$WINDIR\System32\msvcp140.dll"
      StrCpy $0 "missing"
    ${EndIf}
    ${IfNot} ${FileExists} "$WINDIR\System32\vcruntime140_1.dll"
      StrCpy $0 "missing"
    ${EndIf}
    ${EnableX64FSRedirection}
    ${If} $0 == "missing"
      MessageBox MB_OK|MB_ICONINFORMATION "The MySQL client needs Microsoft's Visual C++ 2015-2022 \
        Redistributable (x64), which this PC doesn't seem to have. Install it from Microsoft \
        (search for $\"Visual C++ Redistributable latest$\") before connecting to MySQL."
    ${EndIf}
  SectionEnd
SectionGroupEnd

!insertmacro MUI_FUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${SecApp} "Pagona itself, its license and notices."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecStartMenu} "Pagona in the Start menu, for everyone on this PC."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecDesktop} "A Pagona icon on the desktop, for everyone on this PC."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecLibs} "Only if this PC doesn't already have the client library \
    you need. Oracle (Instant Client) and SQL Server (Microsoft's ODBC driver) are installed separately."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecPg} "libpq from PostgreSQL 18, with OpenSSL 3, put next to pagona.exe."
  !insertmacro MUI_DESCRIPTION_TEXT ${SecMySql} "libmysql from MySQL 8.0, with OpenSSL 3, put next to pagona.exe."
!insertmacro MUI_FUNCTION_DESCRIPTION_END

Section "un.Pagona" UnSecApp
  SectionIn RO
  SetShellVarContext all
  Delete "$SMPROGRAMS\Pagona.lnk"
  Delete "$DESKTOP\Pagona.lnk"
  Delete "$INSTDIR\pagona.exe"
  Delete "$INSTDIR\LICENSE.txt"
  Delete "$INSTDIR\THIRD-PARTY-NOTICES.md"
  Delete "$INSTDIR\README.md"
  Delete "$INSTDIR\libpq.dll"
  Delete "$INSTDIR\libintl-9.dll"
  Delete "$INSTDIR\libiconv-2.dll"
  Delete "$INSTDIR\libwinpthread-1.dll"
  Delete "$INSTDIR\libmysql.dll"
  Delete "$INSTDIR\libssl-3-x64.dll"
  Delete "$INSTDIR\libcrypto-3-x64.dll"
  Delete "$INSTDIR\vcruntime140.dll"
  Delete "$INSTDIR\uninstall.exe"
  RMDir "$INSTDIR"
  DeleteRegKey HKLM "${UNINSTKEY}"
  DeleteRegKey HKLM "Software\Pagona"
SectionEnd

; settings and saved connections stay unless this is ticked; it removes the
; ones of the Windows account running the uninstall (passwords are never saved)
Section /o "un.My settings and saved connections" UnSecSettings
  SetShellVarContext current
  RMDir /r "$LOCALAPPDATA\Pagona"
SectionEnd

!insertmacro MUI_UNFUNCTION_DESCRIPTION_BEGIN
  !insertmacro MUI_DESCRIPTION_TEXT ${UnSecApp} "Pagona and the files it installed."
  !insertmacro MUI_DESCRIPTION_TEXT ${UnSecSettings} "Your Pagona settings and saved connections (in your own \
    Windows profile). Leave unticked to keep them for a later install."
!insertmacro MUI_UNFUNCTION_DESCRIPTION_END
