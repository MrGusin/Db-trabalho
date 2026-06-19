# Integração NoSQL — Aplicativo de Delivery de Comida

Este subprojeto contém a parte **NoSQL** em Java integrada ao banco de dados relacional existente, atendendo a todos os requisitos propostos.

---

## ▌ 1. Justificativa do Modelo NoSQL e CAP Theorem

### Por que MongoDB (NoSQL de Documentos)?
1. **Cardápios com Itens Personalizáveis**:
   - Os produtos do cardápio possuem opções variadas de personalização (ex: bordas, ingredientes extras com custos adicionais). 
   - No SQL relacional, modelar cada permutação de opções gera tabelas altamente normalizadas, joins pesados e esquemas de dados rígidos. 
   - No MongoDB, armazenamos o cardápio e os itens customizados como **documentos semiestruturados**, nos quais cada item possui uma lista dinâmica de possíveis personalizações (`opcoes_personalizacao`).
2. **Avaliações com Fotos**:
   - Uma avaliação pode ter zero, uma ou várias fotos, além de nota, comentário e data.
   - Armazenar arrays dinâmicos de strings (caminhos/URLs das fotos) dentro de um único documento MongoDB é direto, dispensando tabelas associativas no relacional.

### Enquadramento no Teorema CAP:
- **PostgreSQL**: Focado em **Consistência (C)** e **Disponibilidade (A)**. As transações ACID garantem que dados financeiros e de fluxo principal (como criação de pedidos, pagamentos e status) permaneçam sempre consistentes. Em caso de partições de rede, prioriza a consistência dos dados do pedido.
- **MongoDB**: Focado em **Consistência (C)** e **Tolerância a Partição (P)**. O MongoDB garante leituras e escritas consistentes para catálogos de cardápio e avaliações. Se houver uma partição na rede, ele prefere negar acessos temporários para evitar divergência no cardápio de preços.
- **Abordagem Híbrida**: O core transacional e de fluxo fica no PostgreSQL. Caso o MongoDB fique fora do ar durante a compra, a transação no PostgreSQL sofre **Rollback** imediatamente (ou o documento NoSQL é cancelado/descartado), protegendo a integridade financeira e de negócios.

---

## ▌ 2. Integração Híbrida (SQL + NoSQL)

Foi adicionada a coluna `mongodb_item_id VARCHAR(24)` na tabela relacional `pedido_itens` diretamente no arquivo `criacao_banco.sql`:

```sql
CREATE TABLE pedido_itens (
    id                SERIAL      PRIMARY KEY,
    pedido_id         INTEGER     NOT NULL REFERENCES pedido(id),
    produto_id        INTEGER     NOT NULL REFERENCES produto(id),
    quantidade        INTEGER     NOT NULL,
    mongodb_item_id   VARCHAR(24)             -- Referência ao item customizado no MongoDB
);
```

### Fluxo de Gravação Híbrida (Transacional):
1. O Java recebe a solicitação de pedido com as personalizações selecionadas (ex: Borda de Catupiry).
2. Salva o documento de personalização na coleção `pedido_itens_customizados` no MongoDB e obtém o `ObjectId` (24 caracteres hexadecimais).
3. Inicia uma transação JDBC no PostgreSQL (Auto-commit desativado):
   - Insere a cabeçalho do pedido em `pedido`.
   - Insere o item em `pedido_itens`, passando o ID do MongoDB na coluna `mongodb_item_id`.
   - Executa as procedures armazenadas no PostgreSQL via `CallableStatement`:
     - `CALL calcular_taxa_entrega(...)` para computar a taxa de entrega.
     - `CALL atribuir_entregador(...)` que usa cursor para designar o entregador mais próximo.
   - Registra o pagamento pendente em `pagamento`.
   - Faz o **Commit** da transação SQL.
4. **Resiliência a Falhas**: Se houver qualquer falha relacional no PostgreSQL, o Java realiza o **Rollback** na base relacional e remove o documento correspondente do MongoDB, mantendo os dois bancos perfeitamente sincronizados.

---

## ▌ 3. Como Executar o Projeto

### Pré-requisitos
1. **Java Development Kit (JDK 17 ou superior)** instalado.
2. **PostgreSQL** rodando localmente (porta `5432`) com o banco de dados `delivery` criado e configurado (usuário `usuario_dba` e senha `senha_dba123`).
3. **MongoDB** rodando localmente (porta `27017`) sem autenticação.

### Passo 1: Executar o configurador do Maven
Se você não possui o Maven instalado globalmente no Windows, utilize o script na raiz do projeto:
```cmd
..\configura_maven.bat
```
*(Após concluir a instalação automática, feche e abra novamente o seu terminal para atualizar as variáveis de ambiente).*

### Passo 2: Compilar o Projeto Java
Navegue até esta pasta (`nosql-app`) e execute:
```cmd
mvn clean compile
```

### Passo 3: Executar a Aplicação
Execute o comando Maven para iniciar o menu interativo:
```cmd
mvn exec:java
```

---

## ▌ 4. Ações Disponíveis no Menu

Ao iniciar o programa, você verá o seguinte console:

1. **Semear Cardapio com Itens Customizaveis (MongoDB)**: Cria os documentos de produtos personalizáveis no MongoDB com suas respectivas opções e adicionais de preço.
2. **Realizar Novo Pedido Hibrido**: Permite escolher cliente, restaurante, produto base, quantidade e escolher opções de personalização. Salva no MongoDB, cria a transação relacional no PostgreSQL chamando as procedures e associando o `mongodb_item_id`.
3. **Avaliar Restaurante com Fotos (MongoDB)**: Salva avaliações na coleção `avaliacoes` com arrays de caminhos de fotos.
4. **Ver Nota Media de Restaurante (MongoDB Aggregation)**: Roda uma query de agregação no MongoDB agrupando avaliações por restaurante para calcular a nota média real.
5. **Listar Historico de Pedidos com Detalhes (Hibrido)**: Consulta o PostgreSQL para obter os pedidos e realiza a junção dos dados de customizações dinâmicas do MongoDB em tempo de execução.
