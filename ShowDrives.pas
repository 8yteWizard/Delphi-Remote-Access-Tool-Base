unit ShowDrives;

interface

uses
  Winapi.Windows, Winapi.Messages, System.SysUtils, System.Variants, System.Classes, Vcl.Graphics,
  Vcl.Controls, Vcl.Forms, Vcl.Dialogs, Vcl.ComCtrls, System.JSON;

type
  TfrmShowDrives = class(TForm)
    ListView1: TListView;
    procedure FormClose(Sender: TObject; var Action: TCloseAction);
  private
    { Private declarations }
    procedure LoadData(const JSONStr: string);
  public
    { Public declarations }
    class procedure ShowDrives(const HWID, JSONStr: string);
  end;

var
  frmShowDrives: TfrmShowDrives;

implementation

{$R *.dfm}

{ TfrmShowDrives }

class procedure TfrmShowDrives.ShowDrives(const HWID, JSONStr: string);
var
  Form: TfrmShowDrives;
begin
  // Create a new instance of the form
  Form := TfrmShowDrives.Create(Application);
  try
    // Set the window title
    Form.Caption := 'Drive Info: ' + HWID;

    // Load the data
    Form.LoadData(JSONStr);

    // Show the form modelessly (allows multiple windows)
    Form.Show;
  except
    Form.Free;
    raise;
  end;
end;

procedure TfrmShowDrives.FormClose(Sender: TObject; var Action: TCloseAction);
begin
  // Important: Auto-free the form when closed to prevent memory leaks
  Action := caFree;
end;

procedure TfrmShowDrives.LoadData(const JSONStr: string);
var
  jValue: TJSONValue;
  jArr: TJSONArray;
  jObj: TJSONObject;
  i: Integer;
  Li: TListItem;
begin
  ListView1.Clear;
  ListView1.Items.BeginUpdate;
  try
    jValue := TJSONObject.ParseJSONValue(JSONStr);
    try
      if (jValue <> nil) and (jValue is TJSONArray) then
      begin
        jArr := TJSONArray(jValue);

        // Add Columns dynamically based on the first item
        if jArr.Count > 0 then
        begin
          jObj := TJSONObject(jArr.Items[0]);
          for i := 0 to jObj.Count - 1 do
          begin
            ListView1.Columns.Add.Caption := jObj.Pairs[i].JsonString.Value;
            ListView1.Columns[i].Width := 120;
          end;
        end;

        // Populate rows
        for i := 0 to jArr.Count - 1 do
        begin
          if jArr.Items[i] is TJSONObject then
          begin
            jObj := TJSONObject(jArr.Items[i]);
            Li := ListView1.Items.Add;

            // Add first value as Caption
            Li.Caption := jObj.Pairs[0].JsonValue.Value;

            // Add remaining values as SubItems
            for var k := 1 to jObj.Count - 1 do
              Li.SubItems.Add(jObj.Pairs[k].JsonValue.Value);
          end;
        end;
      end;
    finally
      jValue.Free;
    end;
  finally
    ListView1.Items.EndUpdate;
  end;
end;

end.
