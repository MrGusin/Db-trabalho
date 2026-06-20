# Sistema de Delivery - Banco de Dados II

Grupo:Alexandre, Gustavo Chicoski, Katiani, Rayane, Vinicius

Trabalho da disciplina de Banco de Dados II (IFSC Canoinhas). A ideia é um sistema de delivery tipo ifood, usando **PostgreSQL** pra parte relacional (clientes, pedidos, pagamentos, etc) e **MongoDB** pra parte NoSQL (cardápio personalizável e avaliações com fotos).

## Estrutura das pastas

```
Db-trabalho/
├── README.md
├── sql/
│   ├── criacao_banco.sql   -> cria o banco inteiro (tabelas, procedures, triggers, views, roles...)
│   └── testes_banco.sql    -> popula com dados de teste e roda os exemplos pedidos no trabalho
├── nosql-app/               -> app Java que mexe nos dois bancos juntos
│   └── src/main/java/com/delivery/nosql/
│       ├── Main.java                -> menu no terminal
│       ├── ConexaoBanco.java        -> conecta no Postgres e no Mongo
│       └── GerenciadorDelivery.java -> as operações em si (pedido, avaliação, etc)
└── etc/
    ├── configura_banco.bat -> script pra recriar o banco no Windows sem digitar tudo na mão
    ├── backup-e-restore.md -> comandos de backup/restore que usamos
    ├── der-delivery.pdf    -> DER do banco
    └── Requisitos.txt      -> enunciado do trabalho
```

## O que precisa ter instalado

- Java 17+
- Maven
- PostgreSQL 14+
- MongoDB 6+

## Passo 1 - Criar o banco no Postgres

Cria o banco `delivery` (pode ser pelo pgAdmin ou psql) e depois roda o script de criação:

```bash
psql -h localhost -U postgres -d delivery -f sql/criacao_banco.sql
```

Esse script cria as tabelas, as roles/usuários (`usuario_dba`, `usuario_cliente`...), as procedures, triggers, views e os índices. Já deixa tudo pronto.

Se preferir no Windows, dá pra usar o `etc/configura_banco.bat`, que faz isso tudo perguntando usuário/senha.

## Passo 2 - Popular com dados de teste

```bash
psql -h localhost -U postgres -d delivery -f sql/testes_banco.sql
```

Isso cria um restaurante (Pizzaria do Joao, id 1), uma cliente (Ana Souza, id 2), uns entregadores, produtos e um pedido completo passando por todos os status. O app Java usa esses IDs como padrão.

## Passo 3 - Subir o MongoDB

Só precisa estar rodando na porta padrão (27017). Não precisa criar nada manualmente, o banco `delivery_nosql` e as collections são criados sozinhos quando o programa roda.

```bash
# linux
sudo systemctl start mongod

# windows
net start MongoDB
```

## Passo 4 - Rodar o app Java

As credenciais de conexão (usuário/senha do Postgres e Mongo) ficam no `ConexaoBanco.java`, caso precise mudar pro seu ambiente.

```bash
cd nosql-app
mvn compile
mvn exec:java
```

Ou roda direto pela IDE clicando em Run no `Main.java`.

## Menu do programa

```
1. Semear Cardapio com Itens Customizaveis (MongoDB)
2. Realizar Novo Pedido Hibrido (PostgreSQL + MongoDB)
3. Avaliar Restaurante com Fotos (MongoDB)
4. Ver Nota Media de Restaurante (MongoDB Aggregation)
5. Listar Historico de Pedidos com Detalhes (Hibrido)
0. Sair
```

Pra testar tudo, a ordem que faz mais sentido é: roda a opção 1 primeiro (semeia o cardápio no Mongo), depois 2 (faz um pedido), 3 (avalia), 4 (vê a média) e 5 (lista tudo junto).

## Como Postgres e Mongo se conversam

A tabela `pedido_itens` (Postgres) tem uma coluna `mongodb_item_id` que guarda o `_id` do documento de customização lá no Mongo. É basicamente isso que liga os dois bancos: o pedido em si (valor, pagamento, status) fica garantido no Postgres com transação ACID, e a personalização do item (borda, ingrediente extra, observação) fica solta no Mongo sem precisar mexer no schema relacional toda vez que inventar uma opção nova.

## Por que usar os dois bancos (CAP)

O trabalho pede pra justificar com o Teorema CAP. Resumindo bem simples:

- **PostgreSQL = CA** (Consistência + Disponibilidade). Como é tudo ACID com COMMIT/ROLLBACK, dado financeiro (pedido, pagamento) não pode ficar inconsistente, então faz sentido usar ele pra isso.
- **MongoDB = AP** (Disponibilidade + Tolerância a Partição). Não tem schema fixo nem constraint entre as collections, então é mais flexível - serve bem pra coisa que muda de formato de restaurante pra restaurante, tipo as opções do cardápio e as fotos da avaliação.