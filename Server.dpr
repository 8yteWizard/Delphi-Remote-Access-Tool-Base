program Server;

uses
  Vcl.Forms,
  Unit1 in 'Unit1.pas' {Form1},
  Vcl.Themes,
  Vcl.Styles,
  ShowDrives in 'ShowDrives.pas' {Form2},
  ShowProcesses in 'ShowProcesses.pas' {Form3};

{$R *.res}

begin
  Application.Initialize;
  Application.MainFormOnTaskbar := True;
  TStyleManager.TrySetStyle('Jet');
  Application.CreateForm(TForm1, Form1);
  Application.CreateForm(TfrmShowDrives, frmShowDrives);
  Application.CreateForm(TfrmShowProcesses, frmShowProcesses);
  Application.Run;
end.
