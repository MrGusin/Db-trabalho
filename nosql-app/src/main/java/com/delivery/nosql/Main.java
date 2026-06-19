package com.delivery.nosql;

import java.sql.Connection;
import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;
import java.util.Scanner;
import org.bson.Document;
import com.mongodb.client.MongoDatabase;

/**
 * Interface por terminal (Console CLI) para interagir com a aplicação híbrida de delivery.
 */
public class Main {

    public static void main(String[] args) {
        Scanner scanner = new Scanner(System.in);
        Connection conexaoSql = null;
        MongoDatabase bancoMongo = null;
        GerenciadorDelivery gerenciador = null;

        System.out.println("====================================================");
        System.out.println("   SISTEMA DE DELIVERY HIBRIDO (SQL + NOSQL)        ");
        System.out.println("====================================================");
        System.out.println("Tentando conectar aos bancos de dados...");

        try {
            conexaoSql = ConexaoBanco.conectarPostgres();
            System.out.println("[SQL] Conectado ao PostgreSQL (Banco: delivery) com sucesso!");
        } catch (Exception e) {
            System.err.println("[ERRO SQL] Falha ao conectar ao PostgreSQL: " + e.getMessage());
            System.err.println("Certifique-se de ter executado 'criacao_banco.sql' e de que o PostgreSQL esta ativo.");
        }

        try {
            bancoMongo = ConexaoBanco.conectarMongo();
            System.out.println("[NoSQL] Conectado ao MongoDB (Banco: delivery_nosql) com sucesso!");
        } catch (Exception e) {
            System.err.println("[ERRO NoSQL] Falha ao conectar ao MongoDB: " + e.getMessage());
        }

        if (conexaoSql != null && bancoMongo != null) {
            gerenciador = new GerenciadorDelivery(conexaoSql, bancoMongo);
            System.out.println("\n>>> Conexoes estabelecidas! Sistema pronto.");
        } else {
            System.err.println("\n[ATENCAO] Algumas conexoes falharam. O menu podera apresentar erros ao executar as acoes.");
            System.out.println("Deseja continuar assim mesmo? (S/N)");
            String resposta = scanner.nextLine();
            if (!resposta.equalsIgnoreCase("S")) {
                System.out.println("Encerrando a aplicacao.");
                fecharRecursos(conexaoSql);
                return;
            }
            gerenciador = new GerenciadorDelivery(conexaoSql, bancoMongo);
        }

        boolean rodando = true;
        while (rodando) {
            exibirMenu();
            System.out.print("Escolha uma opcao: ");
            String opcao = scanner.nextLine();

            try {
                switch (opcao) {
                    case "1":
                        if (bancoMongo == null) throw new IllegalStateException("MongoDB nao conectado.");
                        gerenciador.semearCardapio();
                        break;

                    case "2":
                        if (conexaoSql == null || bancoMongo == null) {
                            throw new IllegalStateException("Ambos os bancos precisam estar conectados.");
                        }
                        executarPedidoInterativo(gerenciador, scanner);
                        break;

                    case "3":
                        if (bancoMongo == null) throw new IllegalStateException("MongoDB nao conectado.");
                        executarAvaliacaoInterativa(gerenciador, scanner);
                        break;

                    case "4":
                        if (bancoMongo == null) throw new IllegalStateException("MongoDB nao conectado.");
                        executarMédiaAgregada(gerenciador, scanner);
                        break;

                    case "5":
                        if (conexaoSql == null || bancoMongo == null) {
                            throw new IllegalStateException("Ambos os bancos precisam estar conectados.");
                        }
                        gerenciador.listarPedidosComDetalhes();
                        break;

                    case "0":
                        System.out.println("Encerrando o sistema. Obrigado!");
                        rodando = false;
                        break;

                    default:
                        System.out.println("Opcao invalida. Tente novamente.");
                        break;
                }
            } catch (Exception e) {
                System.err.println("\n[ERRO NA OPERACAO] " + e.getMessage());
            }
            System.out.println("\nPressione ENTER para continuar...");
            scanner.nextLine();
        }

        fecharRecursos(conexaoSql);
    }

    private static void exibirMenu() {
        System.out.println("\n====================================================");
        System.out.println("                MENU DE OPCOES                      ");
        System.out.println("====================================================");
        System.out.println("1. Semear Cardapio com Itens Customizaveis (MongoDB)");
        System.out.println("2. Realizar Novo Pedido Hibrido (PostgreSQL + MongoDB)");
        System.out.println("3. Avaliar Restaurante com Fotos (MongoDB - Docs)");
        System.out.println("4. Ver Nota Media de Restaurante (MongoDB Aggregation)");
        System.out.println("5. Listar Historico de Pedidos com Detalhes (Hibrido)");
        System.out.println("0. Sair");
        System.out.println("====================================================");
    }

    private static void executarPedidoInterativo(GerenciadorDelivery gerenciador, Scanner scanner) {
        System.out.println("\n--- Realizar Novo Pedido Hibrido ---");
        System.out.println("Selecione o Cliente (SQL):");
        System.out.println("1. Ana Souza (ID 2 - Conforme seeds)");
        System.out.print("Digite o ID do cliente [Padrao 2]: ");
        String clienteStr = scanner.nextLine();
        int clienteId = clienteStr.trim().isEmpty() ? 2 : Integer.parseInt(clienteStr);

        System.out.println("\nSelecione o Restaurante (SQL):");
        System.out.println("1. Pizzaria do Joao (ID 1 - Conforme seeds)");
        System.out.print("Digite o ID do restaurante [Padrao 1]: ");
        String restStr = scanner.nextLine();
        int restauranteId = restStr.trim().isEmpty() ? 1 : Integer.parseInt(restStr);

        System.out.println("\nSelecione o Produto Base (SQL):");
        System.out.println("1. Pizza Margherita (ID 1)");
        System.out.println("3. Pizza Calabresa (ID 3)");
        System.out.print("Digite o ID do produto [Padrao 1]: ");
        String prodStr = scanner.nextLine();
        int produtoId = prodStr.trim().isEmpty() ? 1 : Integer.parseInt(prodStr);

        System.out.print("Quantidade [Padrao 1]: ");
        String qtdStr = scanner.nextLine();
        int quantidade = qtdStr.trim().isEmpty() ? 1 : Integer.parseInt(qtdStr);

        // Customização
        List<Document> opcoesEscolhidas = new ArrayList<>();
        System.out.println("\nDeseja personalizar este item? (S/N) [Padrao N]: ");
        String resposta = scanner.nextLine();
        if (resposta.equalsIgnoreCase("S")) {
            System.out.println("Escolha a Borda (adicional):");
            System.out.println("1. Borda de Catupiry (+ R$ 5,00)");
            System.out.println("2. Borda de Cheddar (+ R$ 6,00)");
            System.out.println("3. Sem Borda (+ R$ 0,00)");
            System.out.print("Opcao [Padrao 3]: ");
            String bordaOp = scanner.nextLine();
            if (bordaOp.equals("1")) {
                opcoesEscolhidas.add(new Document("categoria", "Borda").append("nome", "Borda de Catupiry").append("adicional", 5.0));
            } else if (bordaOp.equals("2")) {
                opcoesEscolhidas.add(new Document("categoria", "Borda").append("nome", "Borda de Cheddar").append("adicional", 6.0));
            }

            System.out.println("\nDeseja ingrediente extra? (adicional):");
            System.out.println("1. Queijo Extra (+ R$ 4,00)");
            System.out.println("2. Calabresa Extra (+ R$ 5,00)");
            System.out.println("3. Nao");
            System.out.print("Opcao [Padrao 3]: ");
            String extraOp = scanner.nextLine();
            if (extraOp.equals("1")) {
                opcoesEscolhidas.add(new Document("categoria", "Ingrediente Extra").append("nome", "Queijo Extra").append("adicional", 4.0));
            } else if (extraOp.equals("2")) {
                opcoesEscolhidas.add(new Document("categoria", "Ingrediente Extra").append("nome", "Calabresa Extra").append("adicional", 5.0));
            }
        }

        System.out.print("\nObservacao do pedido: ");
        String observacao = scanner.nextLine();

        // Envia para o gerenciador para executar a transação híbrida
        gerenciador.criarPedidoHibrido(clienteId, restauranteId, produtoId, quantidade, opcoesEscolhidas, observacao);
    }

    private static void executarAvaliacaoInterativa(GerenciadorDelivery gerenciador, Scanner scanner) {
        System.out.println("\n--- Avaliar Restaurante com Fotos ---");
        System.out.print("ID do Restaurante [Padrao 1]: ");
        String restStr = scanner.nextLine();
        int restauranteId = restStr.trim().isEmpty() ? 1 : Integer.parseInt(restStr);

        System.out.print("ID do Cliente [Padrao 2]: ");
        String cliStr = scanner.nextLine();
        int clienteId = cliStr.trim().isEmpty() ? 2 : Integer.parseInt(cliStr);

        System.out.print("Nome do Cliente [Padrao 'Ana Souza']: ");
        String nomeCliente = scanner.nextLine();
        if (nomeCliente.trim().isEmpty()) nomeCliente = "Ana Souza";

        System.out.print("Nota de 1 a 5 (ex: 4.5): ");
        double nota = Double.parseDouble(scanner.nextLine());

        System.out.print("Comentario: ");
        String comentario = scanner.nextLine();

        List<String> fotos = new ArrayList<>();
        System.out.println("Digite os caminhos/URLs de fotos (deixe em branco para finalizar):");
        int count = 1;
        while (true) {
            System.out.print("Foto " + count + ": ");
            String foto = scanner.nextLine();
            if (foto.trim().isEmpty()) break;
            fotos.add(foto);
            count++;
        }

        gerenciador.inserirAvaliacaoComFotos(restauranteId, clienteId, nomeCliente, nota, comentario, fotos);
    }

    private static void executarMédiaAgregada(GerenciadorDelivery gerenciador, Scanner scanner) {
        System.out.println("\n--- Obter Nota Media (Aggregation) ---");
        System.out.print("ID do Restaurante [Padrao 1]: ");
        String restStr = scanner.nextLine();
        int restauranteId = restStr.trim().isEmpty() ? 1 : Integer.parseInt(restStr);

        double media = gerenciador.obterNotaMediaRestaurante(restauranteId);
        System.out.printf("[MongoDB Aggregation] A nota media para o restaurante ID %d e: %.2f\n", restauranteId, media);
    }

    private static void fecharRecursos(Connection conexaoSql) {
        try {
            if (conexaoSql != null && !conexaoSql.isClosed()) {
                conexaoSql.close();
                System.out.println("[SQL] Conexao PostgreSQL fechada.");
            }
        } catch (Exception e) {
            System.err.println("Erro ao fechar conexao PostgreSQL: " + e.getMessage());
        }
        ConexaoBanco.fecharMongo();
        System.out.println("[NoSQL] Conexao MongoDB fechada.");
    }
}
