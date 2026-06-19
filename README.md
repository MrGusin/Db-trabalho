# 🛵 Sistema de Delivery Híbrido (SQL + NoSQL)

Projeto acadêmico de Banco de Dados II que demonstra uma arquitetura **híbrida** combinando:
- **PostgreSQL** — dados relacionais (clientes, restaurantes, pedidos, pagamentos)
- **MongoDB** — dados documentais (cardápios personalizáveis, avaliações com fotos, customizações de pedido)

---

## 📁 Estrutura do Projeto

```
Db-trabalho/
│
├── README.md               ← Este arquivo
│
├── sql/                    ← Scripts SQL do PostgreSQL
│   ├── criacao_banco.sql   ← Cria o banco, tabelas, procedures, triggers, views e seeds
│   ├── testes_banco.sql    ← Popula o banco com dados de teste e executa demonstrações
│   └── delivery.sql        ← Versão alternativa/anterior do script SQL
│
├── nosql-app/              ← Aplicação Java (CLI híbrida PostgreSQL + MongoDB)
│   ├── pom.xml             ← Dependências Maven (driver JDBC PostgreSQL + driver MongoDB)
│   └── src/
│       └── main/java/com/delivery/nosql/
│           ├── Main.java                ← Ponto de entrada (menu interativo no terminal)
│           ├── ConexaoBanco.java        ← Gerencia conexões com PostgreSQL e MongoDB
│           └── GerenciadorDelivery.java ← Lógica híbrida de negócio
│
└── etc/                    ← Apenas arquivos de referência
    ├── configura_banco.bat ← Script Windows para configurar o PostgreSQL automaticamente
    ├── backup-e-restore.md ← Comandos de backup e restore com pg_dump e pgBackRest
    ├── der-delivery.pdf    ← Diagrama Entidade-Relacionamento
    └── Requisitos.txt      ← Requisitos do trabalho
```

---

## ✅ Pré-requisitos

Antes de começar, certifique-se de ter instalado:

| Ferramenta | Versão mínima | Download |
|---|---|---|
| Java (JDK) | 17 | https://adoptium.net |
| Apache Maven | 3.8+ | https://maven.apache.org |
| PostgreSQL | 14+ | https://www.postgresql.org/download |
| MongoDB | 6+ | https://www.mongodb.com/try/download/community |

> **Dica:** Se não tiver o Maven instalado, baixe em https://maven.apache.org e adicione ao PATH, ou use `mvnw` se disponível.

---

## 🗄️ Parte 1 — Configurar o PostgreSQL (SQL)

### 1.1 Criar o banco de dados `delivery`

Abra o **pgAdmin** ou o **psql** conectado como superusuário (`postgres`) e execute:

```sql
CREATE DATABASE delivery;
```

### 1.2 Executar o script de criação

Com o banco `delivery` selecionado, execute o script completo:

```bash
psql -h localhost -U postgres -d delivery -f sql/criacao_banco.sql
```

Ou abra o arquivo `sql/criacao_banco.sql` no **pgAdmin** e execute (F5).

Este script cria:
- Usuários e roles (`usuario_dba`, `usuario_cliente`, etc.)
- Todas as tabelas do sistema
- Procedures (`calcular_taxa_entrega`, `atribuir_entregador`)
- Triggers de histórico e de bloqueio por restaurante fechado
- Views (`cardapio_online`, `desempenho_entregadores`)
- Índices de otimização
- Seeds obrigatórios (tipos, status, métodos de pagamento)

### 1.3 Popular com dados de teste (opcional mas recomendado)

```bash
psql -h localhost -U postgres -d delivery -f sql/testes_banco.sql
```

Este script insere:
- 1 restaurante (Pizzaria do Joao — ID 1)
- 1 cliente (Ana Souza — ID 2)
- 2 entregadores
- Produtos, pedidos, pagamentos e histórico completo de status

> ⚠️ **Atenção:** A aplicação Java usa os IDs criados por `testes_banco.sql` como padrão (cliente ID 2, restaurante ID 1, produto ID 1).

---

## 🍃 Parte 2 — Configurar o MongoDB (NoSQL)

### 2.1 Iniciar o serviço do MongoDB

**Windows (serviço):**
```powershell
net start MongoDB
```

**Windows (manual):**
```bash
mongod --dbpath "C:\data\db"
```

**Linux/macOS:**
```bash
sudo systemctl start mongod
```

### 2.2 Verificar a conexão

O MongoDB deve estar acessível em `localhost:27017`.  
O banco de dados utilizado pela aplicação é `delivery_nosql` — ele é criado automaticamente na primeira execução.

Sem necessidade de criar usuários ou collections manualmente. A aplicação cria tudo ao rodar.

---

## ☕ Parte 3 — Compilar e Rodar a Aplicação Java

### 3.1 Verificar a conexão no código (se necessário)

As credenciais estão em `nosql-app/src/main/java/com/delivery/nosql/ConexaoBanco.java`:

```java
// PostgreSQL
private static final String PG_URL  = "jdbc:postgresql://localhost:5432/delivery";
private static final String PG_USER = "usuario_dba";
private static final String PG_PASS = "senha_dba123";

// MongoDB
private static final String MONGO_HOST = "localhost";
private static final int    MONGO_PORT  = 27017;
```

> Esses valores são os mesmos criados pelo script `sql/criacao_banco.sql`. Altere aqui se o seu ambiente for diferente.

### 3.2 Compilar o projeto

```bash
cd nosql-app
mvn compile
```

### 3.3 Executar a aplicação

```bash
mvn exec:java
```

Ou diretamente pela sua IDE (IntelliJ, Eclipse, VS Code) clicando em **Run** na classe `Main.java`.

---

## 🖥️ Menu da Aplicação

Ao iniciar, a aplicação exibe um menu interativo:

```
====================================================
   SISTEMA DE DELIVERY HIBRIDO (SQL + NOSQL)
====================================================

====================================================
                MENU DE OPCOES
====================================================
1. Semear Cardapio com Itens Customizaveis (MongoDB)
2. Realizar Novo Pedido Hibrido (PostgreSQL + MongoDB)
3. Avaliar Restaurante com Fotos (MongoDB - Docs)
4. Ver Nota Media de Restaurante (MongoDB Aggregation)
5. Listar Historico de Pedidos com Detalhes (Hibrido)
0. Sair
====================================================
```

### Ordem recomendada para demonstração:

1. **Opção 1** — Semeia o cardápio no MongoDB (precisa rodar uma vez)
2. **Opção 2** — Cria um pedido híbrido (grava no PostgreSQL + MongoDB)
3. **Opção 3** — Insere uma avaliação com fotos (só MongoDB)
4. **Opção 4** — Consulta nota média usando Aggregation (só MongoDB)
5. **Opção 5** — Lista pedidos integrando os dois bancos

---

## 🔗 Como funciona a integração SQL + NoSQL

```
┌─────────────────────┐         ┌──────────────────────────┐
│     PostgreSQL       │         │         MongoDB           │
│                     │         │                          │
│  pedido_itens       │─────────│  pedido_itens_customizados│
│  mongodb_item_id ───┼────────▶│  _id (ObjectId)          │
│                     │         │  opcoes_escolhidas        │
│  pedido             │         │  observacao               │
│  pagamento          │         │                          │
│  entregador         │         │  cardapios               │
│  restaurante        │         │  avaliacoes              │
└─────────────────────┘         └──────────────────────────┘
```

O campo `mongodb_item_id` na tabela `pedido_itens` (PostgreSQL) armazena o `_id` do documento de customização no MongoDB, criando a ponte entre os dois bancos de forma relacional.

---

## ⚖️ Justificativa do Teorema CAP

O **Teorema CAP** (Brewer, 2000) afirma que um sistema distribuído só pode garantir simultaneamente **dois** dos três atributos abaixo:

| Atributo | Descrição |
|---|---|
| **C**onsistency (Consistência) | Toda leitura reflete a escrita mais recente |
| **A**vailability (Disponibilidade) | Toda requisição recebe uma resposta (sem garantia de ser a mais recente) |
| **P**artition tolerance (Tolerância a Partições) | O sistema continua operando mesmo com falhas de comunicação entre nós |

### PostgreSQL — Classificação: **CA (Consistência + Disponibilidade)**

O PostgreSQL é um banco relacional com foco em consistência forte (ACID). Em uma implantação de nó único (como neste projeto), não há tolerância a partições de rede entre nós, mas as transações garantem:
- **Consistência**: `COMMIT` só acontece após todas as operações serem concluídas com sucesso; `ROLLBACK` automático em falhas.
- **Disponibilidade**: O banco responde a todas as requisições enquanto estiver ativo.
- **Uso neste projeto**: Dados críticos de negócio — pedidos, pagamentos, clientes — onde a integridade referencial e a consistência imediata são obrigatórias.

### MongoDB — Classificação: **AP (Disponibilidade + Tolerância a Partições)**

O MongoDB, em configurações com replica sets ou sharding, prioriza disponibilidade e tolerância a partições. Mesmo em modo de nó único (como neste projeto), a ausência de schema fixo e a escrita eventual são características de um banco AP:
- **Disponibilidade**: Leituras e escritas continuam mesmo durante degradação parcial.
- **Tolerância a Partições**: Nativamente projetado para escalar horizontalmente em clusters distribuídos.
- **Consistência eventual**: No modelo de documentos, não há constraints relacionais entre collections — a consistência é responsabilidade da aplicação.
- **Uso neste projeto**: Dados flexíveis e não-críticos para integridade financeira — cardápios personalizáveis (schema variável por restaurante), avaliações com fotos (arrays de tamanho variável), customizações de pedido (opções livres sem schema fixo).

### Por que a arquitetura híbrida?

A escolha híbrida permite **usar cada banco onde ele é mais forte**:

```
PostgreSQL (CA)                    MongoDB (AP)
━━━━━━━━━━━━━━                     ━━━━━━━━━━━
✔ Integridade referencial          ✔ Schema flexível
✔ Transações ACID                  ✔ Documentos aninhados
✔ Consistência forte               ✔ Arrays e estruturas variáveis
✔ Dados financeiros (pagamentos)   ✔ Cardápios personalizáveis
✔ Regras de negócio (procedures)   ✔ Avaliações com fotos
```

A **ponte entre os paradigmas** é o campo `mongodb_item_id` em `pedido_itens`: a transação financeira fica 100% garantida no PostgreSQL (ACID), enquanto a customização livre do item vive no MongoDB sem engessar o schema relacional.


---

## 🆘 Problemas Comuns

| Erro | Causa provável | Solução |
|---|---|---|
| `ClassNotFoundException: com.delivery.nosql.Main` | Projeto não compilado | Execute `mvn compile` dentro de `nosql-app/` |
| `[ERRO SQL] Falha ao conectar ao PostgreSQL` | PostgreSQL não está rodando ou credenciais erradas | Verifique o serviço e as credenciais em `ConexaoBanco.java` |
| `[ERRO NoSQL] Falha ao conectar ao MongoDB` | MongoDB não está rodando | Execute `net start MongoDB` ou `mongod` |
| `Produto com ID X não encontrado no SQL` | `testes_banco.sql` não foi executado | Execute `sql/testes_banco.sql` antes de rodar a aplicação |
