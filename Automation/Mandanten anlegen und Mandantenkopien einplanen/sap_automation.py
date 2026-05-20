import win32com.client
import sys

# ==================== 核心配置区域 ====================
# 可选值: 'EXCLUSIVE' (专属系统 300-304) 或 'SHARED' (共享系统 300-330)
SYSTEM_TYPE = 'SHARED' 

# 系统的SID前缀（根据截图：Shared系统使用S31，Exclusive系统使用S33）
SYS_PREFIX = 'S31' if SYSTEM_TYPE == 'SHARED' else 'S33'
# ======================================================

# 根据系统类型定义 Client 范围及 SCC4 策略
if SYSTEM_TYPE == 'EXCLUSIVE':
    START_CLIENT = 300
    END_CLIENT = 304
    # 专属系统参数：允许更改/允许跨Client更改
    RADIO_CHANGE_INDEX = 0      # 对应单选框：Änderungen ohne automat. Aufzeichnung
    DROPDOWN_CROSS_CLIENT = "Änderungen an Repository und mand.unabh. Customizing erlaubt"
else:
    START_CLIENT = 300
    END_CLIENT = 330
    # 共享系统参数：完全锁定
    RADIO_CHANGE_INDEX = 2      # 对应单选框：keine Änderungen erlaubt
    DROPDOWN_CROSS_CLIENT = "keine Änderung von Repository- und mand.unabh. Cust.-Obj."

def connect_to_sap():
    """连接到当前运行的 SAP GUI 实例"""
    try:
        SapGuiAuto = win32com.client.GetObject("SAPGUI")
        application = SapGuiAuto.GetScriptingEngine
        connection = application.Connections(0)
        session = connection.Sessions(0)
        return session
    except Exception as e:
        print(f"无法连接到 SAP GUI，请确保 SAP 已登录且开启了 Scripting。错误: {e}")
        sys.exit(1)

def create_logical_systems(session):
    """步骤 1: 批量在 BD54 中创建逻辑系统"""
    print("开始执行 BD54: 创建逻辑系统...")
    session.findById("wnd[0]/tbar[0]/okcd").text = "/nBD54"
    session.findById("wnd[0]").sendVKey(0) # 回车
    
    # 视图通常会弹出一个“警告提示”，按回车确认
    try:
        session.findById("wnd[0]/usr/btn%_GC001001_1001").press() # 确认警告
    except:
        pass

    # 点击 "Neue Einträge" (新条目)
    session.findById("wnd[0]/tbar[1]/btn[5]").press()
    
    # 循环填入逻辑系统
    row = 0
    for client in range(START_CLIENT, END_CLIENT + 1):
        log_sys_name = f"{SYS_PREFIX}CLNT{client}"
        description = f"Client {client} LogSys"
        
        # 写入表格对应的单元格 (根据具体SAP版本，表格控件ID可能略有不同)
        session.findById(f"wnd[0]/usr/tblSAPL0T07TC_LOGSYS/txtLOGSYS-[0,{row}]").text = log_sys_name
        session.findById(f"wnd[0]/usr/tblSAPL0T07TC_LOGSYS/txtBEZEI-[1,{row}]").text = description
        row += 1
        
    # 保存并退出
    session.findById("wnd[0]/tbar[0]/btn[11]").press() # 保存
    session.findById("wnd[0]/tbar[0]/btn[3]").press()  # 返回

def create_clients(session):
    """步骤 2: 批量在 SCC4 中创建 Client 并配置属性"""
    print(f"开始执行 SCC4: 正在配置 {SYSTEM_TYPE} 系统的客户端...")
    
    for client in range(START_CLIENT, END_CLIENT + 1):
        log_sys_name = f"{SYS_PREFIX}CLNT{client}"
        print(f"正在创建 Client: {client} -> 逻辑系统: {log_sys_name}")
        
        session.findById("wnd[0]/tbar[0]/okcd").text = "/nSCC4"
        session.findById("wnd[0]").sendVKey(0)
        
        # 切换到编辑模式 (点击眼镜/铅笔图标)
        try:
            session.findById("wnd[0]/tbar[1]/btn[19]").press()
        except:
            pass # 如果已经在编辑模式则跳过
            
        # 点击 "Neue Einträge" (新条目)
        session.findById("wnd[0]/tbar[1]/btn[5]").press()
        
        # --- 开始填写表单 ---
        session.findById("wnd[0]/usr/txtV_T000-MANDT").text = str(client)
        session.findById("wnd[0]/usr/txtV_T000-MTEXT").text = "Global Bike 4.2 Client"
        session.findById("wnd[0]/usr/txtV_T000-ORT01").text = "München"
        session.findById("wnd[0]/usr/txtV_T000-LOGSYS").text = log_sys_name
        session.findById("wnd[0]/usr/txtV_T000-WAERS").text = "EUR"
        
        # 曼丹角色下拉框 (Training/Education)
        session.findById("wnd[0]/usr/cmbV_T000-CCCATEGORY").key = "T" 
        
        # 核心逻辑：根据系统类型勾选不同的单选框 (Änderungen und Transporte...)
        # 0 = 允许更改不记录, 2 = 不允许更改
        session.findById(f"wnd[0]/usr/radV_T000-CCNOCLIIND[{RADIO_CHANGE_INDEX}]").select()
        
        # 跨Client对象更改下拉框 (Mandantenübergreifende Objektänderungen)
        session.findById("wnd[0]/usr/cmbV_T000-CCDDICIND").text = DROPDOWN_CROSS_CLIENT
        
        # 保护级别：Schutzstufe 0: keine Beschränkung
        session.findById("wnd[0]/usr/cmbV_T000-CCPROTECT").key = "0"
        
        # 限制 eCATT 和 CATT：eCATT und CATT nicht erlaubt
        session.findById("wnd[0]/usr/cmbV_T000-CATTIND").key = " "
        
        # 保存当前 Client
        session.findById("wnd[0]/tbar[0]/btn[11]").press()
        # 返回列表页，准备处理下一个
        session.findById("wnd[0]/tbar[0]/btn[3]").press()

def trigger_client_copy(session):
    """步骤 3: 调用批量拷贝工具"""
    print("所有 Client 创建完毕，正在启动批量拷贝脚本 ZS4S_CLIENT_COPY_CHAIN_GEN...")
    session.findById("wnd[0]/tbar[0]/okcd").text = "/nSE38"
    session.findById("wnd[0]").sendVKey(0)
    session.findById("wnd[0]/usr/txtRS38M-PROGRAMM").text = "ZS4S_CLIENT_COPY_CHAIN_GEN"
    # 后续操作：由于无法得知该自定义程序的具体UI参数，脚本在此停留在界面，
    # 你可以手动填入生成的 Client 范围（300-304 或 300-330）一键触发。
    session.findById("wnd[0]/tbar[1]/btn[8]").press() # 运行程序

if __name__ == "__main__":
    sap_session = connect_to_sap()
    
    # 执行自动化流水线
    create_logical_systems(sap_session)
    create_clients(sap_session)
    trigger_client_copy(sap_session)
    
    print("=== 自动化配置完成 ===")