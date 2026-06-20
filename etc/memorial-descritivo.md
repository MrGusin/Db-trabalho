# Memorial Descritivo — Sistema de Delivery (Banco de Dados II)

## 1. Objetivo

O trabalho é o backend de dados de um sistema de delivery (tipo ifood):
cadastro de restaurante/cliente/entregador, montagem de pedido, cálculo de
taxa de entrega, atribuição de entregador, status do pedido, pagamento,
avaliação do restaurante e cardápio com itens personalizáveis.

## 2. Arquitetura

```
PostgreSQL (delivery)          MongoDB (delivery_nosql)
├─ pessoa, endereco            ├─ cardapios
├─ restaurante, produto        ├─ pedido_itens_customizados
├─ pedido, pedido_itens   <───>│   (ligado via mongodb_item_id)
├─ pagamento                   └─ avaliacoes
├─ entregador
└─ historico_pedido

         ↑                              ↑
         └──────── nosql-app (Java) ────┘
```

Quem fala com os dois bancos ao mesmo tempo é a aplicação Java
(`GerenciadorDelivery.java`), já que não existe integração nativa entre
Postgres e Mongo.

## 3. Modelagem

O modelo completo tá no DER (`der-delivery.pdf`) e detalhado no dicionário
de dados. O enunciado pedia as entidades (restaurante, cardápio, pedido,
entregador, pagamento) mas não dizia como modelar — isso ficou por nossa
conta. Algumas decisões:

- `pessoa` é uma tabela só pra cliente, dono de restaurante e entregador,
  diferenciados pelo `tipo_pessoa_id`. Evita repetir nome/CPF em três
  tabelas e facilita o login.
- Usamos tabelas de domínio (`status_de_pedido`, `tipo_cozinha`,
  `metodo_pagamento`...) em vez de `ENUM` do Postgres ou varchar solto,
  porque é mais fácil adicionar um valor novo (só dar INSERT).
- Conferimos as tabelas pra não ter dependência parcial nem transitiva,
  então o modelo tá normalizado (FNBC). Coisa multivalorada (opções de
  cardápio, fotos) a gente jogou pro MongoDB de propósito.
- Limitação: as colunas de dinheiro (`produto.preco`, `produto.custo`,
  `colaboradores.salario`, `pedido.taxa_entrega`, `pedido.valor_total`)
  ficaram como `real`. O certo seria `NUMERIC(10,2)` pra não ter erro de
  arredondamento, mas não trocamos por falta de tempo.

## 4. Procedures, trigger e cursor

Esses quatro objetos já estavam pedidos no enunciado do tema (procedure de
taxa e de atribuição de entregador com cursor, trigger de histórico e
trigger de bloqueio de restaurante fechado). O que ficou pra gente foi
decidir como implementar cada um.

| Objeto | Tipo | O que faz |
|---|---|---|
| `calcular_taxa_entrega` | procedure | calcula taxa: R$3,00 fixo + R$1,50/km |
| `atribuir_entregador` | procedure com cursor | percorre os entregadores disponíveis e atribui o de menor distância até o restaurante |
| `fn_registrar_historico_pedido` | trigger (AFTER UPDATE) | salva no histórico toda vez que o status do pedido muda |
| `fn_bloquear_restaurante_fechado` | trigger (BEFORE INSERT/UPDATE) | não deixa criar/atualizar pedido se o restaurante estiver fechado |

Usamos cursor de propósito no `atribuir_entregador` porque era um requisito
do trabalho mostrar uso de cursor — sabemos que, na prática, um
`ORDER BY distância LIMIT 1` resolveria igual e até melhor.

## 5. Transação e tratamento de erro

- Fechar um pedido (criar pedido → item → pagamento → atribuir entregador)
  é tratado como uma transação só. Mostramos isso de duas formas:
  - No SQL puro (`testes_banco.sql`), com `BEGIN`/`SAVEPOINT`/
    `ROLLBACK TO SAVEPOINT`/`COMMIT`.
  - No Java (`criarPedidoHibrido`), com `setAutoCommit(false)` e
    `commit()`/`rollback()`.
- O Mongo não participa da transação do Postgres. Então, se a parte
  relacional der erro depois que o documento já foi criado no Mongo, o
  código apaga esse documento manualmente (`deleteOne`) pra não sobrar
  lixo. Não é uma transação distribuída de verdade, é só uma compensação
  feita na mão.
- A trigger de restaurante fechado foi testada no Momento 12 do
  `testes_banco.sql`: fechamos o restaurante, tentamos mexer no pedido
  dentro de um bloco com `EXCEPTION WHEN OTHERS`, a trigger dá
  `RAISE EXCEPTION` e a mensagem de erro aparece capturada.

## 6. SQL mais avançado

- CTEs (`pedidos_por_cliente`, `ranking_entregadores`) pra separar a
  agregação de pedido por cliente do ranking de entregador.
- Window function (`ROW_NUMBER() OVER (...)`) pra ranquear entregador por
  número de entrega sem precisar de subquery aninhada.
- Subquery correlacionada com `EXISTS` pra listar restaurante aberto que
  tenha pelo menos um pedido acima de R$40.
- Não usamos CTE recursiva porque não tem nada hierárquico no modelo
  (tipo árvore de categoria) que justificasse.

## 7. Segurança

O enunciado já pedia roles de cliente, restaurante e entregador, e uma
view de cardápio sem custo interno, e privilégio de alteração de pedido
só pelo próprio dono. Implementamos com quatro roles: `role_dba`,
`role_cliente`, `role_restaurante`, `role_entregador`, com GRANT/REVOKE
até em nível de coluna (ex: `role_entregador` só pode dar UPDATE em
`status` do pedido e em `disponivel`/`latitude`/`longitude` do
entregador).

Também colocamos Row-Level Security na tabela `pedido`: mesmo se o cliente
rodar `SELECT * FROM pedido`, o Postgres filtra e mostra só os pedidos
dele (usando uma função que descobre quem é a pessoa logada). Mesma coisa
pra restaurante e entregador.

A view `cardapio_online` existe só pra não mostrar `produto.custo` pra
quem não devia ver — é a única forma de leitura de produto liberada pro
cliente.

## 8. Backup e restore

O enunciado pedia um plano de backup antes de campanhas e restore de
cardápios. Documentamos em `backup-e-restore.md`: usamos `pg_dump -Fc`
(backup lógico, formato custom) e citamos o `pgBackRest` como alternativa
mais robusta pra produção (backup completo, incremental, diferencial).
Restore lógico com `pg_restore`.

## 9. Otimização

O enunciado já pedia índice em tipo de cozinha e localização, e análise
de EXPLAIN pra busca de restaurante aberto. Além desses, criamos índice
nas outras colunas mais usadas em filtro/JOIN: status do pedido, cliente
e restaurante do pedido, disponibilidade do entregador.

Rodamos três `EXPLAIN ANALYZE` (restaurante aberto por CEP, entregador
disponível, histórico por cliente). Como a base de teste tem pouca linha,
na maioria das consultas o Postgres preferiu `Seq Scan` mesmo com o
índice criado — o que é esperado, porque com tabela pequena o Seq Scan é
mesmo mais barato. Em uma base maior, o índice passaria a ser usado.

## 10. Integração SQL + NoSQL

O enunciado já pedia a parte NoSQL pra cardápio com itens personalizáveis
(documentos) e avaliação com fotos usando aggregation pra nota média, com
o pedido relacional referenciando o documento do item do cardápio. A
ponte entre os dois bancos é a coluna `pedido_itens.mongodb_item_id`,
que guarda o `_id` do documento de customização criado no Mongo. Fluxo do
`criarPedidoHibrido`:

1. Grava a customização no Mongo e pega o `_id` gerado.
2. Abre transação no Postgres: insere pedido, item (com o `_id` do Mongo)
   e pagamento.
3. Chama `atribuir_entregador`.
4. Confirma a transação. Se algo falhar no Postgres, desfaz a transação e
   apaga o documento criado no Mongo.

A leitura (`listarPedidosComDetalhes`) também é híbrida: busca o pedido
no Postgres e, pra cada item que tiver `mongodb_item_id`, busca a
customização no Mongo.

### CAP

- **PostgreSQL → CA**: dado financeiro (pedido, pagamento) precisa de
  ACID, então preferimos consistência mesmo que custe disponibilidade em
  caso de falha.
- **MongoDB → AP**: não tem schema fixo nem constraint entre coleções de
  propósito, porque a personalização de cardápio muda de restaurante pra
  restaurante e não pode exigir migração de schema toda vez.

## 11. Tecnologias

| Camada | Tecnologia |
|---|---|
| Banco relacional | PostgreSQL 14+ |
| Banco não relacional | MongoDB 6+ |
| Aplicação de integração | Java 17 + Maven |
| Driver SQL | PostgreSQL JDBC 42.7.3 |
| Driver NoSQL | MongoDB Java Driver 3.12.14 |
