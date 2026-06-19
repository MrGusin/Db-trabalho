@echo off
setlocal enabledelayedexpansion

echo ===================================================
echo CONFIGURADOR E EXECUTOR AUTOMATICO DO BANCO DE DADOS
echo ===================================================
echo.

:: 1. Procurar o psql.exe
set PSQL_PATH=psql.exe

:: Verifica se o psql já está no PATH do sistema
where psql.exe >nul 2>nul
if %errorlevel% equ 0 (
    echo [INFO] psql encontrado no PATH do sistema.
) else (
    echo [INFO] psql nao esta no PATH. Procurando em pastas padrao do PostgreSQL...
    
    :: Procurar na pasta padrao Program Files
    set FOUND_PSQL=
    for /d %%d in ("C:\Program Files\PostgreSQL\*") do (
        if exist "%%d\bin\psql.exe" (
            set FOUND_PSQL=%%d\bin\psql.exe
        )
    )
    
    if defined FOUND_PSQL (
        set PSQL_PATH="!FOUND_PSQL!"
        echo [INFO] psql encontrado em: !PSQL_PATH!
    ) else (
        echo [ERRO] Nao foi possivel encontrar o psql.exe no PATH ou em C:\Program Files\PostgreSQL.
        echo Por favor, certifique-se de que o PostgreSQL esta instalado.
        pause
        exit /b 1
    )
)

echo.
echo ===================================================
echo CONFIGURACOES DE CONEXAO DO POSTGRES
echo ===================================================

set /p PG_USER="Digite o usuario do PostgreSQL [postgres]: "
if "!PG_USER!"=="" set PG_USER=postgres

set /p PG_HOST="Digite o host do PostgreSQL [localhost]: "
if "!PG_HOST!"=="" set PG_HOST=localhost

set /p PG_PORT="Digite a porta do PostgreSQL [5432]: "
if "!PG_PORT!"=="" set PG_PORT=5432

echo Digite a senha do usuario !PG_USER! (sera ocultada):
for /f "delims=" %%p in ('powershell -Command "$p = Read-Host -AsSecureString; [System.Runtime.InteropServices.Marshal]::PtrToStringAuto([System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($p))"') do (
    set PGPASSWORD=%%p
)

echo.
echo ===================================================
echo [1/2] Limpando conexoes ativas e recriando banco 'delivery'...
echo ===================================================

:: Termina conexões ativas para evitar erros de "database is being accessed by other users"
!PSQL_PATH! -h !PG_HOST! -p !PG_PORT! -U !PG_USER! -d postgres -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname = 'delivery' AND pid <> pg_backend_pid();" >nul 2>&1

:: Limpa dependências de privilégios das roles no banco postgres caso existam (evita erros ao dropar roles)
!PSQL_PATH! -h !PG_HOST! -p !PG_PORT! -U !PG_USER! -d postgres -c "DROP OWNED BY role_dba, role_cliente, role_restaurante, role_entregador;" >nul 2>&1

:: Executa a remoção e recriação do banco
!PSQL_PATH! -h !PG_HOST! -p !PG_PORT! -U !PG_USER! -d postgres -c "DROP DATABASE IF EXISTS delivery;"
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao deletar o banco de dados antigo 'delivery'.
    pause
    exit /b 1
)

!PSQL_PATH! -h !PG_HOST! -p !PG_PORT! -U !PG_USER! -d postgres -c "CREATE DATABASE delivery;"
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao criar o banco de dados 'delivery'.
    pause
    exit /b 1
)

echo.
echo ===================================================
echo [2/2] Executando o script criacao_banco.sql no banco 'delivery'...
echo ===================================================

:: Executa o arquivo SQL diretamente conectado ao banco delivery recém-criado
!PSQL_PATH! -h !PG_HOST! -p !PG_PORT! -U !PG_USER! -d delivery -f "%~dp0criacao_banco.sql"
if %errorlevel% neq 0 (
    echo [ERRO] Falha ao executar o script criacao_banco.sql.
    pause
    exit /b 1
)

echo.
echo ===================================================
echo BANCO DE DADOS CONFIGURADO E INICIALIZADO COM SUCESSO!
echo ===================================================
pause
