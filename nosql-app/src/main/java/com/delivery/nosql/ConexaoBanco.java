package com.delivery.nosql;

import java.sql.Connection;
import java.sql.DriverManager;
import java.sql.SQLException;
import com.mongodb.client.MongoClient;
import com.mongodb.client.MongoClients;
import org.bson.Document;
import com.mongodb.client.MongoDatabase;

/**
 * Classe que cuida das conexoes com os bancos:
 * Postgres (relacional) e MongoDB (NoSQL).
 */
public class ConexaoBanco {

    // dados de conexao do Postgres
    private static final String PG_URL = "jdbc:postgresql://localhost:5432/delivery";
    private static final String PG_USER = "usuario_dba";
    private static final String PG_PASS = "senha_dba123";

    // dados de conexao do Mongo
    private static final String MONGO_HOST = "localhost";
    private static final int MONGO_PORT = 27017;
    private static final String MONGO_DB_NAME = "delivery_nosql";
    private static final String MONGO_USER = "admin";
    private static final String MONGO_PASS = "aluno";
    private static final String MONGO_AUTH_DB = "admin";

    private static MongoClient mongoClient = null;

    // conecta no postgres e devolve a conexao
    public static Connection conectarPostgres() throws SQLException {
        try {
            // carrega o driver JDBC do postgres
            Class.forName("org.postgresql.Driver");
            return DriverManager.getConnection(PG_URL, PG_USER, PG_PASS);
        } catch (ClassNotFoundException e) {
            throw new SQLException("Driver JDBC do PostgreSQL não encontrado no Classpath.", e);
        }
    }

    // conecta no mongo (so conecta uma vez, depois reaproveita)
    public static MongoDatabase conectarMongo() {
        if (mongoClient == null) {
            try {
                String connectionString = "mongodb://localhost:27017";
                mongoClient = MongoClients.create(connectionString);
                // testa se a conexao deu certo
                mongoClient.getDatabase(MONGO_DB_NAME).runCommand(new org.bson.Document("ping", 1));
            } catch (Exception e) {
                System.err.println("\n[AVISO] Não foi possível conectar ao MongoDB em " + MONGO_HOST + ":" + MONGO_PORT);
                System.err.println("Certifique-se de que o serviço do MongoDB está rodando.");
                throw e;
            }
        }
        return mongoClient.getDatabase(MONGO_DB_NAME);
    }

    // fecha a conexao do mongo quando o programa terminar
    public static void fecharMongo() {
        if (mongoClient != null) {
            mongoClient.close();
            mongoClient = null;
        }
    }
}
