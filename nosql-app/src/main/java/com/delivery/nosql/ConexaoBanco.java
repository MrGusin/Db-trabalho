package com.delivery.nosql;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import com.mongodb.client.MongoDatabase;

/**
 * Classe responsável por gerenciar as conexões com os bancos de dados:
 * - PostgreSQL (Relacional)
 * - MongoDB (NoSQL Documentos)
 */
public class ConexaoBanco {

    // Configurações do PostgreSQL
    private static final String PG_URL = "jdbc:postgresql://localhost:5432/delivery";
    private static final String PG_USER = "usuario_dba";
    private static final String PG_PASS = "senha_dba123";

    // Configurações do MongoDB
    private static final String MONGO_HOST = "localhost";
    private static final int MONGO_PORT = 27017;
    private static final String MONGO_DB_NAME = "delivery_nosql";
    // Credenciais de autenticação
    private static final String MONGO_USER = "admin";
    private static final String MONGO_PASS = "aluno";
    private static final String MONGO_AUTH_DB = "admin";

    private static MongoClient mongoClient = null;

    /**
     * Estabelece e retorna uma conexão com o banco de dados PostgreSQL.
     */
    public static Connection conectarPostgres() throws SQLException {
        try {
            // Garante que o driver JDBC do PostgreSQL está carregado
            Class.forName("org.postgresql.Driver");
            return DriverManager.getConnection(PG_URL, PG_USER, PG_PASS);
        } catch (ClassNotFoundException e) {
            throw new SQLException("Driver JDBC do PostgreSQL não encontrado no Classpath.", e);
        }
    }

    /**
     * Estabelece e retorna a referência para o banco de dados MongoDB.
     */
    public static MongoDatabase conectarMongo() {
        if (mongoClient == null) {
            try {
                // Conecta usando o driver MongoDB moderno com autenticação
        String connectionString = String.format("mongodb://%s:%s@%s:%d/?authSource=%s",
                MONGO_USER, MONGO_PASS, MONGO_HOST, MONGO_PORT, MONGO_AUTH_DB);
        mongoClient = MongoClients.create(connectionString);
        // Opcional: validar conexão com ping
        mongoClient.getDatabase(MONGO_DB_NAME).runCommand(new org.bson.Document("ping", 1));
            } catch (Exception e) {
                System.err.println("\n[AVISO] Não foi possível conectar ao MongoDB em " + MONGO_HOST + ":" + MONGO_PORT);
                System.err.println("Certifique-se de que o serviço do MongoDB está rodando.");
                throw e;
            }
        }
        return mongoClient.getDatabase(MONGO_DB_NAME);
    }

    /**
     * Fecha o cliente do MongoDB quando a aplicação for encerrada.
     */
    public static void fecharMongo() {
        if (mongoClient != null) {
            mongoClient.close();
            mongoClient = null;
        }
    }
}
