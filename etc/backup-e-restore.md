# Backup e Restore

## Backup lógico completo

Usado para gerar uma cópia lógica do banco com `pg_dump`:

```bash
pg_dump -h localhost -U postgres -Fc -b -v -f delivery_backup.dump delivery
```

## pgBackRest

Instalação e configuração básica:

```bash
sudo apt update
sudo apt install pgbackrest
sudo mkdir -p /var/lib/pgbackrest
sudo chown postgres:postgres /var/lib/pgbackrest
```

Arquivo de configuração:

```ini
[global]
repo1-path=/var/lib/pgbackrest

[delivery]
pg1-path=/var/lib/postgresql/16/main
```

Backup completo, incremental e diferencial:

```bash
sudo -u postgres pgbackrest --stanza=delivery stanza-create
sudo -u postgres pgbackrest --stanza=delivery backup --type=full
sudo -u postgres pgbackrest --stanza=delivery backup --type=incr
sudo -u postgres pgbackrest --stanza=delivery backup --type=diff
```

## Restore

Restore lógico:

```bash
pg_restore -h localhost -U postgres -d delivery -v delivery_backup.dump
```

Restore com pgBackRest(incremental ou diferencial):

```bash
sudo systemctl stop postgresql
sudo -u postgres pgbackrest --stanza=delivery restore
sudo systemctl start postgresql
```
