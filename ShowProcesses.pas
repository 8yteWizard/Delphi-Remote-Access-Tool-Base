unit ShowProcesses;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, System.JSON, IdContext,
  Vcl.Menus;

type
  TfrmShowProcesses = class(TForm)
    ListView1: TListView;
    PopupMenu1: TPopupMenu;
    Refresh1: TMenuItem;
    KillProcess1: TMenuItem;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
    procedure Refresh1Click(Sender: TObject);
    procedure KillProcess1Click(Sender: TObject);
  private
    { Private declarations }
    FClientContext: TIdContext;
    procedure LoadData(const JSONStr: string);
    // Added the missing declaration here
    procedure ListView1CustomDrawItem(Sender: TCustomListView; Item: TListItem;
      State: TCustomDrawState; var DefaultDraw: Boolean);
  public
    { Public declarations }
    procedure RefreshList;
    class procedure ShowProcesses(const Title, JSONStr: string; AContext: TIdContext);
  end;

var
  frmShowProcesses: TfrmShowProcesses;

implementation

{$R *.dfm}

{ TfrmShowProcesses }

class procedure TfrmShowProcesses.ShowProcesses(const Title, JSONStr: string; AContext: TIdContext);
var
  Form: TfrmShowProcesses;
begin
  Form := TfrmShowProcesses.Create(Application);
  try
    Form.Caption := 'Process Manager: ' + Title;
    Form.FClientContext := AContext;
    Form.LoadData(JSONStr);
    Form.Show;
  except
    Form.Free;
    raise;
  end;
end;

procedure TfrmShowProcesses.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  Action := caFree;
end;

procedure TfrmShowProcesses.Refresh1Click(Sender: TObject);
begin
  // Simply call the public refresh method
  RefreshList;
end;

procedure TfrmShowProcesses.KillProcess1Click(Sender: TObject);
var
  PID: string;
begin
  if ListView1.Selected = nil then Exit;
  if FClientContext = nil then Exit;

  // PID is in SubItems[0] based on LoadData logic below
  if ListView1.Selected.SubItems.Count > 0 then
  begin
    PID := ListView1.Selected.SubItems[0];

    if MessageDlg(Format('Are you sure you want to kill PID %s (%s)?',
       [PID, ListView1.Selected.Caption]), mtConfirmation, [mbYes, mbNo], 0) = mrYes then
    begin
      // Send command asynchronously
      TThread.CreateAnonymousThread(
        procedure
        begin
          try
            if FClientContext.Connection.Connected then
              FClientContext.Connection.IOHandler.WriteLn('KillProcess ' + PID);
          except
            // Handle silent failure
          end;
        end).Start;
    end;
  end;
end;

procedure TfrmShowProcesses.RefreshList;
begin
  if FClientContext = nil then Exit;

  // Ask the client to resend the process list
  TThread.CreateAnonymousThread(
    procedure
    begin
      try
        if FClientContext.Connection.Connected then
          FClientContext.Connection.IOHandler.WriteLn('GetRunningProcesses');
      except
        // Silent fail
      end;
    end).Start;
end;

procedure TfrmShowProcesses.LoadData(const JSONStr: string);
var
  jValue: TJSONValue;
  jArr: TJSONArray;
  jObj: TJSONObject;
  i: Integer;
  Li: TListItem;
  isSelf: Boolean;
begin
  ListView1.Clear;
  ListView1.Items.BeginUpdate;
  try
    // Setup columns
    ListView1.Columns.Clear;
    ListView1.Columns.Add.Caption := 'Process Name';
    ListView1.Columns[0].Width := 250;
    ListView1.Columns.Add.Caption := 'PID';
    ListView1.Columns[1].Width := 80;
    ListView1.Columns.Add.Caption := 'Status';
    ListView1.Columns[2].Width := 100;

    jValue := TJSONObject.ParseJSONValue(JSONStr);
    try
      if (jValue <> nil) and (jValue is TJSONArray) then
      begin
        jArr := TJSONArray(jValue);

        for i := 0 to jArr.Count - 1 do
        begin
          if jArr.Items[i] is TJSONObject then
          begin
            jObj := TJSONObject(jArr.Items[i]);
            Li := ListView1.Items.Add;

            // Extract values
            Li.Caption := jObj.GetValue<string>('process', 'Unknown');

            // Add PID as SubItem[0]
            Li.SubItems.Add(jObj.GetValue<string>('pid', '0'));
            // Add Status as SubItem[1]
            Li.SubItems.Add('Running');

            // Check if this process is the Client (Self)
            isSelf := jObj.GetValue<Boolean>('isSelf', False);

            if isSelf then
            begin
              // We use the Data property to flag this item as "Self".
              // The ListView1CustomDrawItem event will check this flag
              // to draw the text in red.
              Li.Data := Pointer(1);
            end;
          end;
        end;
      end;
    finally
      jValue.Free;
    end;
  finally
    ListView1.Items.EndUpdate;
  end;

  // Hook the event at runtime if it wasn't done in the designer
  if not Assigned(ListView1.OnCustomDrawItem) then
    ListView1.OnCustomDrawItem := ListView1CustomDrawItem;
end;

procedure TfrmShowProcesses.ListView1CustomDrawItem(Sender: TCustomListView;
  Item: TListItem; State: TCustomDrawState; var DefaultDraw: Boolean);
begin
  // If the item was flagged as Self (Client process) in LoadData
  if Item.Data = Pointer(1) then
    Sender.Canvas.Font.Color := clRed
  else
    Sender.Canvas.Font.Color := clWindowText; // Default color

  // Let the ListView draw the item with the updated font color
  DefaultDraw := True;
end;

end.
