@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo INSTALADOR E CONFIGURADOR AUTOMATICO DO MAVEN
echo ===================================================
echo.

set MAVEN_VERSION=3.9.7
set MAVEN_ZIP_URL=https://archive.apache.org/dist/maven/maven-3/!MAVEN_VERSION!/binaries/apache-maven-!MAVEN_VERSION!-bin.zip
set MAVEN_DIR=%USERPROFILE%\maven
set MAVEN_ZIP=%TEMP%\apache-maven-!MAVEN_VERSION!-bin.zip
set MAVEN_HOME_PATH=!MAVEN_DIR!\apache-maven-!MAVEN_VERSION!

echo 1. Baixando Apache Maven !MAVEN_VERSION!...
curl -L -o "!MAVEN_ZIP!" "!MAVEN_ZIP_URL!"
if errorlevel 1 (
    echo [ERRO] Falha ao baixar o Maven. Verifique sua conexao de rede.
    exit /b 1
)

echo.
echo 2. Criando diretorio de destino em: !MAVEN_DIR!
if not exist "!MAVEN_DIR!" mkdir "!MAVEN_DIR!"

echo.
echo 3. Extraindo o arquivo ZIP (isso pode levar alguns instantes)...
powershell -Command "Expand-Archive -Path '!MAVEN_ZIP!' -DestinationPath '!MAVEN_DIR!' -Force"
if errorlevel 1 (
    echo [ERRO] Falha ao extrair o arquivo do Maven.
    exit /b 1
)

echo.
echo 4. Configurando variaveis de ambiente de Usuario...
:: Define MAVEN_HOME no escopo do usuario
setx MAVEN_HOME "!MAVEN_HOME_PATH!" >nul
if errorlevel 1 (
    echo [ERRO] Falha ao configurar a variavel MAVEN_HOME.
    exit /b 1
)
echo Variable MAVEN_HOME configurada para: !MAVEN_HOME_PATH!

:: Adiciona o bin do Maven no Path do usuario com segurança usando PowerShell (evita truncamento)
powershell -Command "$mavenBin = Join-Path $env:USERPROFILE 'maven\apache-maven-!MAVEN_VERSION!\bin'; $userPath = [Environment]::GetEnvironmentVariable('Path', 'User'); if ($userPath -notlike '*apache-maven-!MAVEN_VERSION!*') { [Environment]::SetEnvironmentVariable('Path', $userPath + ';' + $mavenBin, 'User'); Write-Host 'Caminho do Maven adicionado ao Path do Usuario.' } else { Write-Host 'Caminho do Maven ja estava presente no Path do Usuario.' }"

echo.
echo 5. Limpando arquivos temporarios...
del /q "!MAVEN_ZIP!"

echo.
echo ===================================================
echo INSTALACAO CONCLUIDA COM SUCESSO!
echo ===================================================
echo [IMPORTANTE] Por favor, REINICIE o terminal (Prompt ou PowerShell)
echo e o seu editor (VS Code, etc.) para aplicar as novas variaveis de ambiente.
echo.
echo Para testar a instalacao apos reiniciar, execute o comando:
echo   mvn -version
echo ===================================================
pause
