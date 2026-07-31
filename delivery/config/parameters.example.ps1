# Modificare soltanto i percorsi e i nomi non sensibili.
# I timeout PostgreSQL sono facoltativi; questi sono i default operativi.
# $env:POSTGRES_CONNECT_TIMEOUT_SECONDS = '10'
# $env:POSTGRES_LOCK_TIMEOUT_MS = '10000'
# $env:POSTGRES_STATEMENT_TIMEOUT_MS = '120000'
# $env:POSTGRES_IDLE_TRANSACTION_TIMEOUT_MS = '120000'
$driveAuraParameters = @{
    PythonPath = 'C:\Python312\python.exe'
    JavaHome = 'C:\Program Files\Java\jdk-17'
    TomcatHome = 'C:\apache-tomcat-11.0.x'
    PostgresBin = 'C:\Program Files\PostgreSQL\18\bin'
    PostgresHost = '127.0.0.1'
    PostgresPort = 5432
    PostgresUser = 'postgres'
    PostgresDatabase = 'drive_aura_51'
    VerificationDatabase = 'drive_aura_51_verify'
    DjangoPort = 8000
    TomcatPort = 8080
    TomcatShutdownPort = 8005
    SyntheticRemotePort = 8081
}

.\installer\Configure-DriveAura.ps1 @driveAuraParameters
