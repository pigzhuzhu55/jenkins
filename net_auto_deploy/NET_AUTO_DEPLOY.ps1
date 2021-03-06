<#
 *
 *  NET_AUTO_DEPLOY.ps1
 *	
 *	这个PS文件是用于自动打包目录文件、上传到多个服务器后，停掉站点、解压到目标路径、启动站点等一系列自动化部署脚本
 *	（配置见tms_api.xml）。
 *  -- Created by Bob from http://www.cnblogs.com/lavender000/p/6958618.html
 *  -- Modify by caicai
 *  感谢作者 Bob
 #>


param
(
    [parameter(position=0, mandatory=$true)][ValidateNotNullOrEmpty()][string]$Path
)

$lc = @{
   VERBOSE="gray";
   INFO="green";
   WARNING="yellow";
   ERROR="red";
}


#加载依赖
[System.Reflection.Assembly]::Load("WindowsBase,
   Version=3.0.0.0, Culture=neutral, PublicKeyToken=31bf3856ad364e35")

function log([string] $level, [string] $message)
{
    $date = get-date -uformat "%G-%m-%d %T"
	write-host "[$date] " -nonewline
    write-host -foregroundcolor $lc[$level] $level.padright(7)  -nonewline
    write-host -foregroundcolor $lc[$level] " $message"
}

#遍历文件夹并打包压缩到压缩包
function loopDirAndPkg([System.IO.Packaging.ZipPackage] $pkg1,[string] $sourceFilePath1,[string] $rootDir1)
{
    #如果是文件，直接压缩进来
    if((Get-Item $sourceFilePath1) -is [IO.FileInfo])
    {
        $uriString = $sourceFilePath1.Replace($rootDir1,"").Replace("\","/");
        $partName=New-Object System.Uri($uriString, [System.UriKind]"Relative")
	    $pkgPart=$pkg1.CreatePart($partName, "application/zip",
		    [System.IO.Packaging.CompressionOption]"Maximum")
	    $bytes=[System.IO.File]::ReadAllBytes($sourceFilePath1)
	    $stream=$pkgPart.GetStream()
	    $stream.Seek(0, [System.IO.SeekOrigin]"Begin");
	    $stream.Write($bytes, 0, $bytes.Length)
	    $stream.Close()
    }
    else{
         foreach($ItemInfo in (Get-ChildItem -Path $sourceFilePath1))
	    {
            #log INFO ($ItemInfo.FullName)
            loopDirAndPkg $pkg1 $ItemInfo.FullName $rootDir1
        }       
    }
}
 
Set-StrictMode -version latest

$ConfigData = [XML](Get-Content $Path)
$Servers = $ConfigData.NET_AUTO_DEPLOY.Servers
$IISSite = $ConfigData.NET_AUTO_DEPLOY.IISSite
$SourceItems = $ConfigData.NET_AUTO_DEPLOY.Source.Items
$DestinationFolder = $ConfigData.NET_AUTO_DEPLOY.DestinationFolder
$BackupFolder = $ConfigData.NET_AUTO_DEPLOY.BackupFolder

$localHost = [System.Environment]::MachineName


log INFO ("开始压缩要发布的文件")

#遍历取根目录
$rootDir = ""
foreach ($Item in $SourceItems.ChildNodes)
{
		if ($Item -is [System.Xml.XmlComment])
		{
			continue
		}
		$sourceFilePath = $Item.InnerText
        
		if ($sourceFilePath -ne $null -and $sourceFilePath -ne "")
		{
			if (!(Test-Path -path $sourceFilePath))
			{
				log ERROR ("Cannot find path ($sourceFilePath) maybe it does not exist. Please check your configuration file.")
			}
			else 
			{   
                $dirName = $sourceFilePath
				 if((Get-Item $sourceFilePath) -is [IO.DirectoryInfo])
                 {
                 }
                 else
                 {
                    $dirName = $sourceFilePath.Substring(0,$sourceFilePath.LastIndexOf("\"))

                    $fileName = $sourceFilePath.Substring( $sourceFilePath.LastIndexOf("\")+1)
                     
                 }


                 
                 if($rootDir -eq "")
                 {
                    $rootDir = $dirName
                 }
                 else
                 {
                    if($rootDir.contains($dirName))
                    {
                        $rootDir = $dirName
                    }
                 }
			}
		}
	}

#压缩到去掉根目录的统一压缩包
$ZipPath = $rootDir+"\old.zip";
log INFO($ZipPath)
#删除已有的压缩包
if (Test-Path($ZipPath))
{
	Remove-Item $ZipPath
}

#打开压缩包
$pkg=[System.IO.Packaging.ZipPackage]::Open($ZipPath,
    [System.IO.FileMode]"OpenOrCreate", [System.IO.FileAccess]"ReadWrite")


foreach ($Item in $SourceItems.ChildNodes)
{
	if ($Item -is [System.Xml.XmlComment])
	{
		continue
	}
	$sourceFilePath = $Item.InnerText
        
	if ($sourceFilePath -ne $null -and $sourceFilePath -ne "")
	{
		if (!(Test-Path -path $sourceFilePath))
		{
			log ERROR ("Cannot find path ($sourceFilePath) maybe it does not exist. Please check your configuration file.")
		}
		else 
		{   
			loopDirAndPkg $pkg $sourceFilePath $rootDir
		}
	}
}

#关闭压缩包
$pkg.Close()

log INFO ("压缩完毕")

log INFO ("准备发布")

log INFO ("")

#遍历发布到目标服务器
$ComputerArray = New-Object System.Collections.ArrayList
foreach ($Comp in $Servers.ChildNodes)
{
    $IP = $Comp.IP
    $User = $Comp.User
    $PWord = ConvertTo-SecureString -String $Comp.PWord -AsPlainText -Force
    $Credential = New-Object -TypeName System.Management.Automation.PSCredential -ArgumentList $User, $PWord
    
    log WARNING ("开始发布服务器：$IP")
	$sourceSession = New-PSSession -ComputerName $IP -Credential $Credential

	log INFO ("停掉站点：($IISSite)")
    Invoke-Command -Session $sourceSession -ScriptBlock {
        param($site) 
        New-Alias -name appcmd -value $env:windir\system32\inetsrv\appcmd.exe
        appcmd stop site $site
    } -ArgumentList $IISSite
    
    log INFO ("开始备份站点的发布目录")
    
    Invoke-Command -Session $sourceSession -ScriptBlock {
        param($dstinationFolder,$backupFolder)
        if (!(Test-Path -path $backupFolder))
        {
            New-Item $backupFolder -Type Directory
        }
        $usedate = "{0:yyyy-MM-dd}" -f (get-date)
        Compress-Archive -Path $dstinationFolder -DestinationPath $backupFolder\$usedate.zip -Force

        $backupNum = 5
        #保留最后5个备份
        $files = Get-ChildItem -Path $backupFolder | Sort-Object -Property LastWriteTime -Descending | Select-Object -Skip $backupNum
        if ($files.count -gt 0) {
            foreach($file in $files)
            {
                Remove-Item $file.FullName -Recurse -Force
            }
        }

    } -ArgumentList $DestinationFolder,$BackupFolder

    log INFO ("备份完成")

	log INFO ("开始上传文件到服务器")

    Copy-Item -Path $ZipPath -Destination $DestinationFolder -ToSession $sourceSession -Recurse -Force 

	log INFO ("文件上传完毕")

    log INFO ("开始远程解压")

    Invoke-Command -Session $sourceSession -ScriptBlock {
        param($destinationFolder)
        $zipDir = $destinationFolder+"\old.zip"
        Expand-Archive -Path $zipDir -DestinationPath $destinationFolder -Force
        Remove-Item -Path $zipDir -Force

    } -ArgumentList $DestinationFolder

    
    log INFO ("远程解压完毕")


	log INFO ("重新启动站点：($IISSite)")
    Invoke-Command -Session $sourceSession -ScriptBlock {
        param($site) 
        appcmd start site $site
    } -ArgumentList $IISSite

    Remove-PSSession -Session $sourceSession

    log WARNING ("服务器：$IP 发布完成")
    
    log INFO ("")
}