object frmShowProcesses: TfrmShowProcesses
  Left = 0
  Top = 0
  Caption = 'Processes Info'
  ClientHeight = 400
  ClientWidth = 600
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
    Width = 600
    Height = 400
    Align = alClient
    Columns = <>
    ReadOnly = True
    RowSelect = True
    PopupMenu = PopupMenu1
    TabOrder = 0
    ViewStyle = vsReport
  end
  object PopupMenu1: TPopupMenu
    Left = 320
    Top = 200
    object Refresh1: TMenuItem
      Caption = 'Refresh'
      OnClick = Refresh1Click
    end
    object KillProcess1: TMenuItem
      Caption = 'Kill Process'
      OnClick = KillProcess1Click
    end
  end
end
