# Dicionário de Dados — Sistema de Delivery

Este documento descreve todas as tabelas do banco relacional (PostgreSQL), as
views, os índices e as coleções do banco não relacional (MongoDB) usados no
projeto. 

## Convenções

- **PK** = chave primária · **FK** = chave estrangeira · **UQ** = restrição única
- Tipos `SERIAL` aparecem como `integer` com `nextval(...)` de default (sequência)
- Todas as tabelas vivem no schema `public`

---

## 1. Tabelas de domínio (tipos/status)

Tabelas pequenas, usadas como "enum" para não deixar string solta espalhada
pelo banco. Todas seguem o mesmo padrão: `id SERIAL PK` + uma coluna de texto.

| Tabela | Coluna | Tipo | Null? | Descrição | Valores carregados (seed) |
|---|---|---|---|---|---|
| `tipo_cadastro` | id | integer | não | PK | — |
| | tipo | varchar(2) | não | Tipo de pessoa jurídica/física | `PF`, `PJ` |
| `tipo_pessoa` | id | integer | não | PK | — |
| | tipo | varchar(20) | não | Papel da pessoa no sistema | `Cliente`, `Restaurante`, `Entregador` |
| `status_de_pedido` | id | integer | não | PK | — |
| | status | varchar(20) | não | Estágio do pedido | `Pendente`, `Aceito`, `Em preparo`, `Saiu para entrega`, `Entregue` |
| `metodo_pagamento` | id | integer | não | PK | — |
| | metodo | varchar(20) | não | Forma de pagamento | `Cartão de Crédito`, `Cartão de Débito`, `Pix` |
| `status_pagamento` | id | integer | não | PK | — |
| | status | varchar(10) | não | Situação do pagamento | `Pendente`, `Pago` |
| `tipo_logradouro` | id | integer | não | PK | — |
| | tipo | varchar(15) | não | Tipo de logradouro do endereço | `Rua`, `Avenida`, `Alameda`, `Travessa`, `Estrada`, `Rodovia`, `Praça`, `Largo`, `Viela`, `Beco`, `Quadra`, `Setor`, `Condomínio`, `Fazenda`, `Sítio` |
| `tipo_cozinha` | id | integer | não | PK | — |
| | tipo | varchar(30) | não | Categoria culinária do restaurante | `Pizzaria`, `Hamburgueria`, `Japonês / Sushi`, `Churrascaria`, `Italiana`, `Mexicana`, `Árabe / Mediterrânea`, `Chinesa`, `Brasileira`, `Vegetariana / Vegana`, `Frutos do Mar / Peixaria`, `Cafeteria`, `Padaria / Confeitaria`, `Fast Food`, `Lanchonete`, `Sorvetes e Açaí`, `Peruana`, `Contemporânea / Bistrô` |

---

## 2. `estado`

Estado (UF) usado no endereço.

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| nome | varchar(50) | não | — | Nome do estado. **UQ** |

---

## 3. `cidade`

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| nome | varchar(100) | não | — | Nome da cidade |
| estado_id | integer | não | — | **FK** → `estado.id` |

**UQ**: `(nome, estado_id)` — não permite duas cidades de mesmo nome no mesmo estado.

---

## 4. `pessoa`

Tabela central de identidade: clientes, donos de restaurante e entregadores são
todos uma `pessoa`, diferenciados por `tipo_pessoa_id`.

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| pessoa_id | integer | não | `nextval` | **PK** |
| cpf_cnpj | varchar(14) | sim | — | CPF (PF) ou CNPJ (PJ). **UQ**. `CHECK`: tamanho deve ser 11 ou 14 |
| nome | varchar(100) | não | — | Nome / razão social |
| login_usuario | varchar(50) | sim | — | Login usado para RLS (ver seção de segurança). **UQ** |
| tipo_cadastro | integer | não | — | **FK** → `tipo_cadastro.id` (PF/PJ) |
| tipo_pessoa_id | integer | não | — | **FK** → `tipo_pessoa.id` (Cliente/Restaurante/Entregador) |

---

## 5. `endereco`

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id_endereco | integer | não | `nextval` | **PK** |
| id_pessoa | integer | não | — | **FK** → `pessoa.pessoa_id` |
| cep | varchar(9) | sim | — | CEP |
| tipo_logradouro_id | integer | sim | — | **FK** → `tipo_logradouro.id` |
| logradouro | varchar(100) | sim | — | Nome da rua/avenida |
| cidade_id | integer | não | — | **FK** → `cidade.id` |
| numero | integer | sim | — | Número do imóvel |
| bairro | varchar(60) | sim | — | Bairro |
| tipo_endereco | varchar(20) | sim | — | Ex.: `residencial`, `comercial` |
| latitude | numeric | sim | — | Coordenada (usada no cálculo de distância) |
| longitude | numeric | sim | — | Coordenada (usada no cálculo de distância) |

---

## 6. `restaurante`

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| pessoa_id | integer | não | — | **FK** → `pessoa.pessoa_id` (dono/PJ) |
| nome | varchar(100) | não | — | Nome fantasia |
| status_funcionamento | boolean | não | `false` | Se está aberto agora (usado pela trigger de bloqueio) |
| tipo_cozinha_id | integer | não | — | **FK** → `tipo_cozinha.id` |

---

## 7. `produto`

Item do cardápio (parte relacional — preço e custo "oficiais"; a
personalização fica no MongoDB).

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| nome | varchar(100) | não | — | Nome do produto |
| tipo | varchar(30) | sim | — | Categoria (Pizza, Bebida...) |
| preco | real | sim | — | Preço de venda |
| custo | real | sim | — | Custo interno (**nunca exposto** na view `cardapio_online`) |
| restaurante_id | integer | não | — | **FK** → `restaurante.id` |

---

## 8. `colaboradores`

Funcionários vinculados a um restaurante (não é dono nem cliente nem entregador).

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| pessoa_id | integer | não | — | **FK** → `pessoa.pessoa_id` |
| restaurante_id | integer | não | — | **FK** → `restaurante.id` |
| cargo | varchar(50) | sim | — | Função exercida |
| salario | real | sim | — | Salário (mesma observação de tipo do item 7) |

---

## 9. `entregador`

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| pessoa_id | integer | não | — | **FK** → `pessoa.pessoa_id` |
| disponivel | boolean | não | `false` | Se está livre para receber pedido (usado por `atribuir_entregador`) |
| latitude | numeric | sim | — | Posição atual |
| longitude | numeric | sim | — | Posição atual |

---

## 10. `pedido`

Tabela mais central do modelo — o pedido em si.

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| cliente_id | integer | não | — | **FK** → `pessoa.pessoa_id` |
| restaurante_id | integer | não | — | **FK** → `restaurante.id` |
| entregador_id | integer | sim | — | **FK** → `entregador.id` (nulo até `atribuir_entregador` rodar) |
| status | integer | não | — | **FK** → `status_de_pedido.id` |
| data_hora | timestamp | sim | — | Data/hora de criação |
| taxa_entrega | real | sim | — | Calculada por `calcular_taxa_entrega` |
| valor_total | real | sim | — | Valor total cobrado |

Protegida por **Row-Level Security** (cada role só enxerga/edita os pedidos
relacionados a ela — ver memorial descritivo, seção Segurança).

---

## 11. `pedido_itens`

Itens de um pedido. É a tabela-ponte com o MongoDB.

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| pedido_id | integer | não | — | **FK** → `pedido.id` |
| produto_id | integer | não | — | **FK** → `produto.id` |
| quantidade | integer | não | — | Quantidade do item |
| mongodb_item_id | varchar(24) | sim | — | `_id` (ObjectId em hex) do documento de customização na coleção `pedido_itens_customizados` do MongoDB. **Não é FK de banco** — é referência lógica, mantida pela aplicação Java |

---

## 12. `pagamento`

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| pedido_id | integer | não | — | **FK** → `pedido.id` |
| metodo_id | integer | não | — | **FK** → `metodo_pagamento.id` |
| status_id | integer | não | — | **FK** → `status_pagamento.id` |

---

## 13. `historico_pedido`

Populada automaticamente pela trigger `trg_historico_pedido` a cada mudança
de status do pedido.

| Coluna | Tipo | Null? | Default | Descrição |
|---|---|---|---|---|
| id | integer | não | `nextval` | **PK** |
| pedido_id | integer | não | — | **FK** → `pedido.id` |
| status_anterior_id | integer | não | — | **FK** → `status_de_pedido.id` |
| status_novo_id | integer | não | — | **FK** → `status_de_pedido.id` |
| data_alteracao | timestamp | não | `now()` | Momento da mudança |

---

## 14. Views

| View | Tipo | Descrição |
|---|---|---|
| `cardapio_online` | View comum | Espelha `produto`, mas **omite a coluna `custo`** — é a view de segurança que o cliente final enxerga (role `role_cliente` só tem `GRANT SELECT` nela, nunca na tabela `produto` crua) |
| `desempenho_entregadores` | View materializada | Agrega, por entregador: total de entregas (`COUNT`) e taxa média de entrega (`AVG`). Atualizada com `REFRESH MATERIALIZED VIEW CONCURRENTLY` após cargas de dados, evitando recalcular a agregação a cada consulta |

---

## 15. Índices

| Índice | Tabela | Coluna(s) | Motivação |
|---|---|---|---|
| `idx_produto_tipo` | produto | tipo | Filtro por categoria de produto |
| `idx_restaurante_tipo_cozinha` | restaurante | tipo_cozinha_id | Busca de restaurantes por tipo de cozinha (pedido explícito do enunciado) |
| `idx_endereco_cep` | endereco | cep | Busca por localização/CEP (pedido explícito do enunciado) |
| `idx_endereco_coordenadas` | endereco | (latitude, longitude) | Apoio a cálculo de distância/raio |
| `idx_pedido_status` | pedido | status | Filtros por status do pedido |
| `idx_pedido_cliente` | pedido | cliente_id | Histórico de pedidos por cliente (RLS e consultas do app) |
| `idx_pedido_restaurante` | pedido | restaurante_id | Pedidos por restaurante |
| `idx_restaurante_status` | restaurante | status_funcionamento | Busca de "restaurantes abertos agora" |
| `idx_entregador_disponivel` | entregador | disponivel | Apoio ao cursor de `atribuir_entregador` |
| `idx_desempenho_entregador_id` | desempenho_entregadores | entregador_id (único) | Permite `REFRESH ... CONCURRENTLY` na view materializada |

---

## 16. Roles (papéis de acesso)

| Role | Login associado | Pode |
|---|---|---|
| `role_dba` | usuario_dba | Acesso total (DDL/DML em tudo) |
| `role_cliente` | usuario_cliente | Ver `cardapio_online`, criar/ver os **próprios** pedidos, pagamentos e itens |
| `role_restaurante` | usuario_restaurante | Gerenciar `produto`, ver/atualizar pedidos do **próprio** restaurante |
| `role_entregador` | usuario_entregador | Ver pedidos atribuídos a si, atualizar status/disponibilidade/localização |

Detalhe de implementação: o isolamento "só vejo o que é meu" é reforçado por
**Row-Level Security** na tabela `pedido`, usando funções (`fn_pessoa_id_do_usuario`,
`fn_restaurante_id_do_usuario`, `fn_entregador_id_do_usuario`) que descobrem
quem está logado via `current_user` / `login_usuario`.

---

## 17. Coleções MongoDB (banco `delivery_nosql`)

A parte NoSQL guarda informação flexível — que muda de formato com frequência
e não precisa de integridade referencial forte — mantendo a parte financeira
("dinheiro de verdade") inteiramente no PostgreSQL.

### `cardapios`

Cardápio com opções de personalização (estrutura aninhada, sem schema fixo).

| Campo | Tipo | Descrição |
|---|---|---|
| `_id` | ObjectId | Identificador do documento |
| `restaurante_id_sql` | int | Referência lógica a `restaurante.id` (Postgres) |
| `produto_id_sql` | int | Referência lógica a `produto.id` (Postgres) |
| `nome` | string | Nome do item |
| `preco_base` | double | Preço base (espelha `produto.preco`) |
| `opcoes_personalizacao` | array de objetos | Cada item tem `categoria` (ex.: "Bordas") e `opcoes` (array de `{nome, adicional}`) |

### `pedido_itens_customizados`

Customização escolhida pelo cliente para um item específico de um pedido.

| Campo | Tipo | Descrição |
|---|---|---|
| `_id` | ObjectId | **Este valor é gravado em `pedido_itens.mongodb_item_id` (Postgres)** — é a ponte entre os dois bancos |
| `produto_id_sql` | int | Referência lógica a `produto.id` |
| `opcoes_escolhidas` | array de objetos | Opções selecionadas (`nome`, `categoria`, `adicional`) |
| `observacao` | string | Observação livre do cliente |
| `total_adicionais` | double | Soma dos adicionais escolhidos |

### `avaliacoes`

Avaliação do restaurante, com fotos.

| Campo | Tipo | Descrição |
|---|---|---|
| `_id` | ObjectId | Identificador do documento |
| `restaurante_id_sql` | int | Referência lógica a `restaurante.id` |
| `cliente_id_sql` | int | Referência lógica a `pessoa.pessoa_id` |
| `cliente_nome` | string | Nome do cliente (desnormalizado de propósito, para não precisar de JOIN no Mongo) |
| `nota` | double | Nota da avaliação |
| `comentario` | string | Comentário livre |
| `fotos` | array de string | Caminhos/URLs das fotos anexadas |
| `data_avaliacao` | date | Data da avaliação |

> Nas três coleções, os campos `*_id_sql` são **referências lógicas**, não
> constraints de banco — o MongoDB não garante que aquele id realmente existe
> no PostgreSQL. Quem garante essa coerência é a aplicação Java
> (`GerenciadorDelivery`), inclusive desfazendo o documento do Mongo se a
> transação correspondente no Postgres falhar.
