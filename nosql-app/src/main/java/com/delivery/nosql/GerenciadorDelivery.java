package com.delivery.nosql;

import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.CallableStatement;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.Date;
import java.util.List;

import org.bson.Document;
import org.bson.types.ObjectId;

import com.mongodb.client.MongoCollection;
import com.mongodb.client.MongoDatabase;
import com.mongodb.client.model.Accumulators;
import com.mongodb.client.model.Aggregates;
import com.mongodb.client.model.Filters;

/**
 * Classe com as operacoes do sistema que mexem nos dois bancos juntos:
 * semear cardapio, fazer pedido, avaliar restaurante, ver media e listar pedidos.
 */
public class GerenciadorDelivery {

    private final Connection conexaoSql;
    private final MongoDatabase bancoMongo;

    public GerenciadorDelivery(Connection conexaoSql, MongoDatabase bancoMongo) {
        this.conexaoSql = conexaoSql;
        this.bancoMongo = bancoMongo;
    }

    // limpa e cria o cardapio com itens personalizaveis no mongo
    public void semearCardapio() {
        MongoCollection<Document> colecaoCardapio = bancoMongo.getCollection("cardapios");
        colecaoCardapio.drop(); // apaga o que tinha antes pra nao duplicar

        // pizza margherita (restaurante 1, produto 1 no sql)
        Document pizzaMargherita = new Document()
                .append("restaurante_id_sql", 1)
                .append("produto_id_sql", 1)
                .append("nome", "Pizza Margherita")
                .append("preco_base", 45.00)
                .append("opcoes_personalizacao", Arrays.asList(
                        new Document("categoria", "Bordas")
                                .append("opcoes", Arrays.asList(
                                        new Document("nome", "Sem Borda").append("adicional", 0.0),
                                        new Document("nome", "Borda de Catupiry").append("adicional", 5.0),
                                        new Document("nome", "Borda de Cheddar").append("adicional", 6.0))),
                        new Document("categoria", "Ingredientes Extras")
                                .append("opcoes", Arrays.asList(
                                        new Document("nome", "Queijo Extra").append("adicional", 4.0),
                                        new Document("nome", "Manjericão Extra").append("adicional", 2.0)))));

        // pizza calabresa (restaurante 1, produto 3 no sql)
        Document pizzaCalabresa = new Document()
                .append("restaurante_id_sql", 1)
                .append("produto_id_sql", 3)
                .append("nome", "Pizza Calabresa")
                .append("preco_base", 49.00)
                .append("opcoes_personalizacao", Arrays.asList(
                        new Document("categoria", "Bordas")
                                .append("opcoes", Arrays.asList(
                                        new Document("nome", "Sem Borda").append("adicional", 0.0),
                                        new Document("nome", "Borda de Catupiry").append("adicional", 5.0),
                                        new Document("nome", "Borda de Cheddar").append("adicional", 6.0))),
                        new Document("categoria", "Ingredientes Extras")
                                .append("opcoes", Arrays.asList(
                                        new Document("nome", "Calabresa Extra").append("adicional", 5.0),
                                        new Document("nome", "Cebola Extra").append("adicional", 1.0)))));

        colecaoCardapio.insertOne(pizzaMargherita);
        colecaoCardapio.insertOne(pizzaCalabresa);

        System.out.println("[MongoDB] Cardapio semeado com itens personalizaveis!");
    }

    // cria um pedido novo, gravando a parte fixa no postgres e a customizacao no mongo
    public void criarPedidoHibrido(int clienteId, int restauranteId, int produtoId, int quantidade,
            List<Document> opcoesEscolhidas, String observacao) {

        System.out.println("\n--- Iniciando criacao de pedido hibrido ---");

        // 1. salva a customizacao no mongo primeiro
        MongoCollection<Document> colecaoCustomizados = bancoMongo.getCollection("pedido_itens_customizados");

        double valorAdicionais = 0.0;
        for (Document opcao : opcoesEscolhidas) {
            valorAdicionais += opcao.getDouble("adicional");
        }

        Document customizacaoDoc = new Document()
                .append("produto_id_sql", produtoId)
                .append("opcoes_escolhidas", opcoesEscolhidas)
                .append("observacao", observacao)
                .append("total_adicionais", valorAdicionais);

        colecaoCustomizados.insertOne(customizacaoDoc);
        ObjectId mongoId = customizacaoDoc.getObjectId("_id");
        String mongoIdStr = mongoId.toHexString();
        System.out.println("[MongoDB] Customizacao criada com ID NoSQL: " + mongoIdStr);

        // 2. agora comeca a transacao no postgres
        try {
            conexaoSql.setAutoCommit(false);

            // pega o preco base do produto
            double precoBase = 0.0;
            String queryPreco = "SELECT preco FROM produto WHERE id = ?";
            try (PreparedStatement psPreco = conexaoSql.prepareStatement(queryPreco)) {
                psPreco.setInt(1, produtoId);
                try (ResultSet rsPreco = psPreco.executeQuery()) {
                    if (rsPreco.next()) {
                        precoBase = rsPreco.getDouble("preco");
                    } else {
                        throw new SQLException("Produto com ID " + produtoId + " nao encontrado no SQL.");
                    }
                }
            }

            // calcula o valor total do item (preco + adicionais) * quantidade
            double valorTotalItem = (precoBase + valorAdicionais) * quantidade;

            // insere o pedido com status Pendente
            int pedidoId = -1;
            String sqlPedido = "INSERT INTO pedido (cliente_id, restaurante_id, status, data_hora, taxa_entrega, valor_total) "
                    +
                    "VALUES (?, ?, (SELECT id FROM status_de_pedido WHERE status = 'Pendente' LIMIT 1), NOW(), NULL, ?) "
                    +
                    "RETURNING id";
            try (PreparedStatement psPedido = conexaoSql.prepareStatement(sqlPedido)) {
                psPedido.setInt(1, clienteId);
                psPedido.setInt(2, restauranteId);
                psPedido.setDouble(3, valorTotalItem);
                try (ResultSet rsPedido = psPedido.executeQuery()) {
                    if (rsPedido.next()) {
                        pedidoId = rsPedido.getInt(1);
                    }
                }
            }

            if (pedidoId == -1) {
                throw new SQLException("Falha ao inserir o pedido no PostgreSQL.");
            }
            System.out.println("[PostgreSQL] Pedido criado com ID SQL: " + pedidoId);

            // Inserir item do pedido relacionando com o documento do MongoDB
            String sqlItem = "INSERT INTO pedido_itens (pedido_id, produto_id, quantidade, mongodb_item_id) VALUES (?, ?, ?, ?)";
            try (PreparedStatement psItem = conexaoSql.prepareStatement(sqlItem)) {
                psItem.setInt(1, pedidoId);
                psItem.setInt(2, produtoId);
                psItem.setInt(3, quantidade);
                psItem.setString(4, mongoIdStr); // aqui que liga com o documento do mongo
                psItem.executeUpdate();
            }
            System.out.println("[PostgreSQL] Item do pedido inserido com link para o NoSQL.");

            // chama a procedure pra calcular a taxa de entrega
            double distanciaFakeKm = 3.5; // distancia simulada, fixa so pra testar
            float taxaEntrega = 0.0f;
            String sqlTaxa = "CALL calcular_taxa_entrega(?, ?)";
            try (CallableStatement csTaxa = conexaoSql.prepareCall(sqlTaxa)) {
                csTaxa.setDouble(1, distanciaFakeKm);
                csTaxa.registerOutParameter(2, java.sql.Types.REAL);
                csTaxa.execute();
                taxaEntrega = csTaxa.getFloat(2);
            }
            System.out.println("[PostgreSQL] Chamada a procedure calcular_taxa_entrega: R$ " + taxaEntrega);

            // atualiza o pedido com a taxa e o valor final
            double valorFinalPedido = valorTotalItem + taxaEntrega;
            String sqlUpdatePedido = "UPDATE pedido SET taxa_entrega = ?, valor_total = ? WHERE id = ?";
            try (PreparedStatement psUpdate = conexaoSql.prepareStatement(sqlUpdatePedido)) {
                psUpdate.setFloat(1, taxaEntrega);
                psUpdate.setDouble(2, valorFinalPedido);
                psUpdate.setInt(3, pedidoId);
                psUpdate.executeUpdate();
            }

            // cria o pagamento como pendente
            String sqlPagamento = "INSERT INTO pagamento (pedido_id, metodo_id, status_id) " +
                    "VALUES (?, (SELECT id FROM metodo_pagamento WHERE metodo = 'Pix' LIMIT 1), " +
                    "(SELECT id FROM status_pagamento WHERE status = 'Pendente' LIMIT 1))";
            try (PreparedStatement psPag = conexaoSql.prepareStatement(sqlPagamento)) {
                psPag.setInt(1, pedidoId);
                psPag.executeUpdate();
            }

            // chama a procedure que escolhe o entregador mais perto (usa cursor)
            String sqlEntregador = "CALL atribuir_entregador(?)";
            try (CallableStatement csEntregador = conexaoSql.prepareCall(sqlEntregador)) {
                csEntregador.setInt(1, pedidoId);
                csEntregador.execute();
            }
            System.out.println("[PostgreSQL] Chamada a procedure atribuir_entregador com cursor executada.");

            // deu tudo certo, confirma a transacao
            conexaoSql.commit();
            System.out.println("[ACID] Transacao SQL confirmada! Pedido finalizado com sucesso.");

        } catch (Exception e) {
            // deu erro em algum passo, desfaz tudo que ja tinha rodado no postgres
            try {
                conexaoSql.rollback();
                // se foi a trigger que bloqueou (restaurante fechado), mostra mensagem mais clara
                if (e instanceof java.sql.SQLException) {
                    java.sql.SQLException sqlEx = (java.sql.SQLException) e;
                    if ("P0001".equals(sqlEx.getSQLState())) {
                        System.err.println("[ERRO] Pedido bloqueado: o restaurante esta fechado no momento.");
                        System.err.println("       Aguarde o restaurante abrir e tente novamente.");
                    } else {
                        System.err.println("[ROLLBACK] Erro durante gravacao do pedido relacional. Rollback executado: "
                                + e.getMessage());
                    }
                } else {
                    System.err.println("[ROLLBACK] Erro durante gravacao do pedido relacional. Rollback executado: "
                            + e.getMessage());
                }
            } catch (java.sql.SQLException ex) {
                System.err.println("Erro ao executar rollback: " + ex.getMessage());
            }

            // o mongo nao tem rollback automatico junto com o postgres, entao
            // se o sql falhou a gente apaga na mao o documento que tinha acabado de criar
            colecaoCustomizados.deleteOne(Filters.eq("_id", mongoId));
            System.err.println("[MongoDB] Documento de customizacao NoSQL deletado devido a falha relacional.");
        } finally {
            try {
                conexaoSql.setAutoCommit(true);
            } catch (java.sql.SQLException e) {
                System.err.println("Erro ao redefinir auto-commit: " + e.getMessage());
            }
        }
    }

    // salva uma avaliacao do restaurante com nota, comentario e fotos no mongo
    public void inserirAvaliacaoComFotos(int restauranteId, int clienteId, String nomeCliente, double nota,
            String comentario, List<String> caminhosFotos) {
        MongoCollection<Document> colecaoAvaliacoes = bancoMongo.getCollection("avaliacoes");

        Document avaliacao = new Document()
                .append("restaurante_id_sql", restauranteId)
                .append("cliente_id_sql", clienteId)
                .append("cliente_nome", nomeCliente)
                .append("nota", nota)
                .append("comentario", comentario)
                .append("fotos", caminhosFotos)
                .append("data_avaliacao", new Date());

        colecaoAvaliacoes.insertOne(avaliacao);
        System.out.println("[MongoDB] Avaliacao inserida para o Restaurante " + restauranteId + " com "
                + caminhosFotos.size() + " foto(s)!");
    }

    // calcula a nota media das avaliacoes de um restaurante usando aggregation do mongo
    public double obterNotaMediaRestaurante(int restauranteId) {
        MongoCollection<Document> colecaoAvaliacoes = bancoMongo.getCollection("avaliacoes");

        // filtra pelo restaurante e tira a media das notas
        List<Document> resultado = colecaoAvaliacoes.aggregate(Arrays.asList(
                Aggregates.match(Filters.eq("restaurante_id_sql", restauranteId)),
                Aggregates.group("$restaurante_id_sql", Accumulators.avg("notaMedia", "$nota"))))
                .into(new ArrayList<>());

        if (!resultado.isEmpty()) {
            return resultado.get(0).getDouble("notaMedia");
        }
        return 0.0;
    }

    // lista os pedidos do postgres e busca a customizacao de cada item no mongo
    public void listarPedidosComDetalhes() {
        String sql = "SELECT p.id AS pedido_id, pes.nome AS cliente, r.nome AS restaurante, " +
                "pi.quantidade, pr.nome AS produto, pi.mongodb_item_id, p.valor_total, s.status " +
                "FROM pedido p " +
                "JOIN pessoa pes ON pes.pessoa_id = p.cliente_id " +
                "JOIN restaurante r ON r.id = p.restaurante_id " +
                "JOIN pedido_itens pi ON pi.pedido_id = p.id " +
                "JOIN produto pr ON pr.id = pi.produto_id " +
                "JOIN status_de_pedido s ON s.id = p.status " +
                "ORDER BY p.id DESC";

        MongoCollection<Document> colecaoCustomizados = bancoMongo.getCollection("pedido_itens_customizados");

        try (Statement stmt = conexaoSql.createStatement();
                ResultSet rs = stmt.executeQuery(sql)) {

            System.out.println(
                    "\n=========================================================================================");
            System.out.println(
                    "                 LISTAGEM INTEGRADA DE PEDIDOS (POSTGRESQL + MONGODB)                    ");
            System.out.println(
                    "=========================================================================================");

            boolean temPedidos = false;
            while (rs.next()) {
                temPedidos = true;
                int pedidoId = rs.getInt("pedido_id");
                String cliente = rs.getString("cliente");
                String restaurante = rs.getString("restaurante");
                int qtd = rs.getInt("quantidade");
                String produtoName = rs.getString("produto");
                String mongoId = rs.getString("mongodb_item_id");
                double total = rs.getDouble("valor_total");
                String status = rs.getString("status");

                System.out.printf("Pedido #%d | Cliente: %s | Restaurante: %s | Status: %s | Total: R$ %.2f\n",
                        pedidoId, cliente, restaurante, status, total);
                System.out.printf("  -> Item: %d x %s (SQL)\n", qtd, produtoName);

                // busca a customizacao no mongo, se o item tiver uma
                if (mongoId != null && !mongoId.trim().isEmpty()) {
                    Document customDoc = colecaoCustomizados.find(Filters.eq("_id", new ObjectId(mongoId))).first();
                    if (customDoc != null) {
                        System.out.println("  -> [MongoDB] Customizacoes:");
                        List<Document> opcoes = (List<Document>) customDoc.get("opcoes_escolhidas");
                        if (opcoes != null && !opcoes.isEmpty()) {
                            for (Document op : opcoes) {
                                System.out.printf("     * %s (%s): +R$ %.2f\n",
                                        op.getString("nome"), op.getString("categoria"), op.getDouble("adicional"));
                            }
                        }
                        String obs = customDoc.getString("observacao");
                        if (obs != null && !obs.trim().isEmpty()) {
                            System.out.println("     * Observacao: \"" + obs + "\"");
                        }
                    } else {
                        System.out.println("  -> [MongoDB] Customizacoes nao localizadas para o ID: " + mongoId);
                    }
                } else {
                    System.out.println("  -> Sem customizacoes (Item Simples).");
                }
                System.out.println(
                        "-----------------------------------------------------------------------------------------");
            }
            if (!temPedidos) {
                System.out.println("Nenhum pedido cadastrado no momento.");
            }
        } catch (SQLException e) {
            System.err.println("Erro ao listar pedidos integrados: " + e.getMessage());
        }
    }
}
