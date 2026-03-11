object frmShowDrives: TfrmShowDrives
  Left = 0
  Top = 0
  Caption = 'Drive Info'
  ClientHeight = 300
  ClientWidth = 500
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnClose = FormClose
  TextHeight = 15
  object ListView1: TListView
    Left = 0
    Top = 0
    Width = 500
    Height = 300
    Align = alClient
    Columns = <>
    ReadOnly = True
    RowSelect = True
    TabOrder = 0
    ViewStyle = vsReport
  end
end
