# Jenkins+Powershell+SVN  基于IIS、.NET Framework的web站点自动化部署

## 前置条件以及环境
- windows服务器(一台部署jenkins、其他服务器装IIS用于站点部署、所有服务器都要安装powershell)
- IIS + .NET Framework
- powershell
- svn(也可以是git)
- jenkins
- vs2017（最好在jenkins的服务器上也安装它，且跟你开发的版本一致，不然构建代码的时候会报各种依赖异常，你要一个一个去指定路径并排除）
## 本文涉及的环境说明
- 服务器3台
	--192.168.2.10 jenkins+vs2017+powershell
	--192.168.2.21 powershell+iis站点
	--192.168.2.22 powershell+iis站点
- iis Web站点标识为  www.test.com ，我直接用域名来标记站点的名称，这里1个站点2个部署，用于测试自动部署到多个服务器
- powershell用于脚本去同步文件、站点停止、启动

## 前置步骤
**假定你的所有环境都安装完毕的情况下，我这里的演示不在同一个域里面的服务器，PowerShell 默认的远程连接是通过winrm实现的。在域内很容易，一般指定域名就可以直接连接了，如果希望连接工作组的机器，或者我就想用IP地址连远程访问，添加IP地址到指定的TrustedHost即可**

###powershell的配置以及端口开放
- 在服务器上以管理员权限运行,开启远程管理
> Enable-PSRemoting -Force

- 信任IP *表示接受所有ip,也可以用通配符
> Set-Item WSMan:\localhost\Client\TrustedHosts -Value * -Force
- 查看当前TrustedHosts信任的IP
> Get-Item WSMan:\localhost\Client\TrustedHosts | Select-Object Value

- 防火墙
> New-NetFirewallRule -Name powershell-remote-tcp -Direction Inbound -DisplayName 'PowerShell远程连接 TCP' -> LocalPort 5985-5996 -Protocol 'TCP'
> New-NetFirewallRule -Name powershell-remote-udp -Direction Inbound -DisplayName 'PowerShell远程连接 UDP' -> > LocalPort 5985-5996 -Protocol 'UDP'

- 导入IIS管理模块
> Import-Module WebAdministration

**其他一些有用到的脚本**
- 使用appcmd.exe：
> New-Alias -name appcmd -value $env:windir\system32\inetsrv\appcmd.exe
这样就可以在当前PS环境下直接使用appcmd了
- 停止站点
> appcmd stop site "www.test.com"
- 开启站点
> appcmd start site "www.test.com"

- 用户凭证
> $User = "administrator"
> $PWord = ConvertTo-SecureString -String "zqhl.jsb.12306" -AsPlainText -Force
> $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
- 远程powershell
> Enter-PSSession -ComputerName 192.168.2.18 -Credential $Credential
- 退出远程powershell
> Exit-Pssession

## jenkins插件安装
 **安装的时候，推荐默认安装一些常用的插件，这里就这次部署，我们还需要安装如下插件**
 系统管理--插件管理--可选插件
> 选中 MSBuild Plugin、Subversion Plug-in、PowerShell plugin  安装后重启下jenkins

## 新建一个任务的所有步骤以及配置
- 新建任务
>- 构建一个自由风格的软件项目--[test]
 - 源码管理--我这里用的是svn,所以选择Subversion--输入路径以及身份验证
 - 构建触发器--根据需要自己选择
 - 构建 -- Build a Visual Studio project or solution using MSBuild --这里如果没用选项卡，需要你去全局工具配置里面增加MSBuild的配置后就会有的。
 - 构建 -- Windows PowerShell -- 
      D:\jenkins\net_auto_deploy\NET_AUTO_DEPLOY.ps1 -Path D:\jenkins\net_auto_deploy\tms_api.xml
 - 保存

## 立即构建
