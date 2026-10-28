#ifndef AppVersion
  #define AppVersion "0.1.0"
#endif
[Setup]
AppId={{DC64F670-D5E9-4B19-809C-5B0C3B1964E1}
AppName=Al Hassan Online Quran Academy
AppVersion={#AppVersion}
AppPublisher=Al Hassan Online Quran Academy
DefaultDirName={localappdata}\Programs\AlHassanAcademy
DefaultGroupName=Al Hassan Academy
PrivilegesRequired=lowest
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
MinVersion=10.0.19045
OutputDir=output
OutputBaseFilename=AlHassanAcademy-Setup-{#AppVersion}-windows-x64
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayIcon={app}\desktop\AlHassanAcademy.exe
AppMutex=Local\AlHassanAcademyServer
CloseApplications=yes
RestartApplications=no
SetupLogging=yes
[Files]
Source: "bundle\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs
[Icons]
Name: "{group}\Al Hassan Academy"; Filename: "{app}\AlHassanLauncher.exe"; WorkingDir: "{app}"
Name: "{autodesktop}\Al Hassan Academy"; Filename: "{app}\AlHassanLauncher.exe"; WorkingDir: "{app}"
[Run]
Filename: "{app}\AlHassanLauncher.exe"; Description: "Start Al Hassan Academy"; Flags: nowait postinstall skipifsilent
; Deliberately no UninstallDelete entry: database, configuration, backups, and
; Quran cache live outside {app} and must survive updates and uninstall.
