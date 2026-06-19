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
 * Gerencia a lógica híbrida (PostgreSQL + MongoDB):
 * 1. Semear Cardápio Customizável (MongoDB)
 * 2. Realizar Pedido Híbrido (Gravação transacional SQL + Gravação do ID NoSQL)
 * 3. Inserir Avaliações com Fotos (MongoDB)
 * 4. Calcular Nota Média do Restaurante usando Aggregation (MongoDB)
 * 5. Listar Pedidos mostrando detalhes relacionais e NoSQL integrados
 */
public class GerenciadorDelivery {

    private final Connection conexaoSql;
    private final MongoDatabase bancoMongo;

    public GerenciadorDelivery(Connection conexaoSql, MongoDatabase bancoMongo) {
        this.conexaoSql = conexaoSql;
        this.bancoMongo = bancoMongo;
    }

    /**
     * Requisito: "NoSQL para cardápios com itens personalizáveis (documentos)"
     * Limpa e semeia o cardápio de produtos customizáveis no MongoDB.
     */
    public void semearCardapio() {
        MongoCollection<Document> colecaoCardapio = bancoMongo.getCollection("cardapios");
        colecaoCardapio.drop(); // Limpa dados anteriores para demonstração limpa

        // Exemplo 1: Pizza Margherita (Restaurante ID 1, Produto ID 1 no SQL)
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
                        new Document("nome", "Borda de Cheddar").append("adicional", 6.0)
                    )),
                new Document("categoria", "Ingredientes Extras")
                    .append("opcoes", Arrays.asList(
                        new Document("nome", "Queijo Extra").append("adicional", 4.0),
                        new Document("nome", "Manjericão Extra").append("adicional", 2.0)
                    ))
            ));

        // Exemplo 2: Pizza Calabresa (Restaurante ID 1, Produto ID 3 no SQL)
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
                        new Document("nome", "Borda de Cheddar").append("adicional", 6.0)
                    )),
                new Document("categoria", "Ingredientes Extras")
                    .append("opcoes", Arrays.asList(
                        new Document("nome", "Calabresa Extra").append("adicional", 5.0),
                        new Document("nome", "Cebola Extra").append("adicional", 1.0)
                    ))
            ));

        colecaoCardapio.insertOne(pizzaMargherita);
        colecaoCardapio.insertOne(pizzaCalabresa);

        System.out.println("[MongoDB] Cardapio semeado com itens personalizaveis!");
    }

    /**
     * Requisito: "integração onde o pedido relacional referência o documento do item do cardápio"
     * Cria um pedido híbrido.
     */
    public void criarPedidoHibrido(int clienteId, int restauranteId, int produtoId, int quantidade,
                                   List<Document> opcoesEscolhidas, String observacao) {
        
        System.out.println("\n--- Iniciando criacao de pedido hibrido ---");

        // 1. Salvar personalizações no MongoDB (pedido_itens_customizados)
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

        // 2. Iniciar Transação ACID no PostgreSQL
        try {
            conexaoSql.setAutoCommit(false);

            // Obter preço base do produto no SQL
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

            // Calcular valor total do item
            double valorTotalItem = (precoBase + valorAdicionais) * quantidade;

            // Inserir registro de pedido (Pendente)
            int pedidoId = -1;
            String sqlPedido = "INSERT INTO pedido (cliente_id, restaurante_id, status, data_hora, taxa_entrega, valor_total) " +
                               "VALUES (?, ?, (SELECT id FROM status_de_pedido WHERE status = 'Pendente' LIMIT 1), NOW(), NULL, ?) " +
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
                psItem.setString(4, mongoIdStr); // SALVA A REFERÊNCIA NOSQL AQUI!
                psItem.executeUpdate();
            }
            System.out.println("[PostgreSQL] Item do pedido inserido com link para o NoSQL.");

            // Calcular Taxa de Entrega chamando a PROCEDURE SQL
            double distanciaFakeKm = 3.5; // Distância simulada
            float taxaEntrega = 0.0f;
            String sqlTaxa = "CALL calcular_taxa_entrega(?, ?)";
            try (CallableStatement csTaxa = conexaoSql.prepareCall(sqlTaxa)) {
                csTaxa.setDouble(1, distanciaFakeKm);
                csTaxa.registerOutParameter(2, java.sql.Types.REAL);
                csTaxa.execute();
                taxaEntrega = csTaxa.getFloat(2);
            }
            System.out.println("[PostgreSQL] Chamada a procedure calcular_taxa_entrega: R$ " + taxaEntrega);

            // Atualizar o valor_total do pedido adicionando a taxa de entrega
            double valorFinalPedido = valorTotalItem + taxaEntrega;
            String sqlUpdatePedido = "UPDATE pedido SET taxa_entrega = ?, valor_total = ? WHERE id = ?";
            try (PreparedStatement psUpdate = conexaoSql.prepareStatement(sqlUpdatePedido)) {
                psUpdate.setFloat(1, taxaEntrega);
                psUpdate.setDouble(2, valorFinalPedido);
                psUpdate.setInt(3, pedidoId);
                psUpdate.executeUpdate();
            }

            // Inserir registro de pagamento pendente
            String sqlPagamento = "INSERT INTO pagamento (pedido_id, metodo_id, status_id) " +
                                  "VALUES (?, (SELECT id FROM metodo_pagamento WHERE metodo = 'Pix' LIMIT 1), " +
                                  "(SELECT id FROM status_pagamento WHERE status = 'Pendente' LIMIT 1))";
            try (PreparedStatement psPag = conexaoSql.prepareStatement(sqlPagamento)) {
                psPag.setInt(1, pedidoId);
                psPag.executeUpdate();
            }

            // Atribuir entregador automaticamente usando a PROCEDURE com CURSOR
            String sqlEntregador = "CALL atribuir_entregador(?)";
            try (CallableStatement csEntregador = conexaoSql.prepareCall(sqlEntregador)) {
                csEntregador.setInt(1, pedidoId);
                csEntregador.execute();
            }
            System.out.println("[PostgreSQL] Chamada a procedure atribuir_entregador com cursor executada.");

            // Confirmar Transação
            conexaoSql.commit();
            System.out.println("[ACID] Transacao SQL confirmada! Pedido finalizado com sucesso.");

        } catch (Exception e) {
            // Em caso de erro, rollback completo das alterações relacionais
            try {
                conexaoSql.rollback();
                System.err.println("[ROLLBACK] Erro durante gravacao do pedido relacional. Rollback executado: " + e.getMessage());
            } catch (SQLException ex) {
                System.err.println("Erro ao executar rollback: " + ex.getMessage());
            }
            
            // O MongoDB não suporta rollback de escrita simples sem réplica configurada para transações,
            // mas como boa prática, podemos remover o documento de customização NoSQL caso o SQL falhe.
            colecaoCustomizados.deleteOne(Filters.eq("_id", mongoId));
            System.err.println("[MongoDB] Documento de customizacao NoSQL deletado devido a falha relacional.");
        } finally {
            try {
                conexaoSql.setAutoCommit(true);
            } catch (SQLException e) {
                System.err.println("Erro ao redefinir auto-commit: " + e.getMessage());
            }
        }
    }

    /**
     * Requisito: "NoSQL para avaliações com fotos (documentos)"
     * Salva uma avaliação com array de caminhos/URLs de fotos no MongoDB.
     */
    public void inserirAvaliacaoComFotos(int restauranteId, int clienteId, String nomeCliente, double nota, String comentario, List<String> caminhosFotos) {
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
        System.out.println("[MongoDB] Avaliacao inserida para o Restaurante " + restauranteId + " com " + caminhosFotos.size() + " foto(s)!");
    }

    /**
     * Requisito: "aggregation para nota média"
     * Executa o framework de Aggregation do MongoDB para obter a nota média de um restaurante.
     */
    public double obterNotaMediaRestaurante(int restauranteId) {
        MongoCollection<Document> colecaoAvaliacoes = bancoMongo.getCollection("avaliacoes");

        // Pipeline de Aggregation:
        // 1. Filtrar pelo restaurante ($match)
        // 2. Agrupar e calcular a média ($group com $avg)
        List<Document> resultado = colecaoAvaliacoes.aggregate(Arrays.asList(
            Aggregates.match(Filters.eq("restaurante_id_sql", restauranteId)),
            Aggregates.group("$restaurante_id_sql", Accumulators.avg("notaMedia", "$nota"))
        )).into(new ArrayList<>());

        if (!resultado.isEmpty()) {
            return resultado.get(0).getDouble("notaMedia");
        }
        return 0.0;
    }

    /**
     * Demonstra a leitura híbrida coerente entre os dois paradigmas.
     * Lista os pedidos do PostgreSQL e lê as personalizações associadas no MongoDB.
     */
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

            System.out.println("\n=========================================================================================");
            System.out.println("                 LISTAGEM INTEGRADA DE PEDIDOS (POSTGRESQL + MONGODB)                    ");
            System.out.println("=========================================================================================");
            
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

                // Busca a customização no MongoDB caso o ID exista na coluna
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
                System.out.println("-----------------------------------------------------------------------------------------");
            }
            if (!temPedidos) {
                System.out.println("Nenhum pedido cadastrado no momento.");
            }
        } catch (SQLException e) {
            System.err.println("Erro ao listar pedidos integrados: " + e.getMessage());
        }
    }
}
