-- ============================================================
--  SISTEMA DE DELIVERY — BANCO DE DADOS II
--  Script de criação e execução real do banco
-- ============================================================

-- ================================================================
-- ▌ PARTE 0 — CRIAÇÃO DO BANCO E SCHEMA
-- ================================================================

-- Bloco PL/pgSQL para remover dependências locais das roles com segurança se existirem
DO $$
BEGIN
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_dba') THEN
        EXECUTE 'DROP OWNED BY role_dba;';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_cliente') THEN
        EXECUTE 'DROP OWNED BY role_cliente;';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_restaurante') THEN
        EXECUTE 'DROP OWNED BY role_restaurante;';
    END IF;
    IF EXISTS (SELECT 1 FROM pg_roles WHERE rolname = 'role_entregador') THEN
        EXECUTE 'DROP OWNED BY role_entregador;';
    END IF;
END;
$$;

-- Remove usuários antigos se existirem
DROP USER IF EXISTS usuario_dba;
DROP USER IF EXISTS usuario_cliente;
DROP USER IF EXISTS usuario_restaurante;
DROP USER IF EXISTS usuario_entregador;

-- Remove roles antigas se existirem
DROP ROLE IF EXISTS role_dba;
DROP ROLE IF EXISTS role_cliente;
DROP ROLE IF EXISTS role_restaurante;
DROP ROLE IF EXISTS role_entregador;

-- Criação das roles (sem permissão de login)
CREATE ROLE role_dba         NOLOGIN;
CREATE ROLE role_cliente     NOLOGIN;
CREATE ROLE role_restaurante NOLOGIN;
CREATE ROLE role_entregador  NOLOGIN;

-- Permissões iniciais do DBA no banco e no schema
GRANT ALL PRIVILEGES ON DATABASE delivery TO role_dba;
GRANT USAGE, CREATE ON SCHEMA public TO role_dba;

-- Configura privilégios padrão para futuros objetos criados no schema public pelo executor do script
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON TABLES TO role_dba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON SEQUENCES TO role_dba;
ALTER DEFAULT PRIVILEGES IN SCHEMA public GRANT ALL PRIVILEGES ON FUNCTIONS TO role_dba;

-- Criação dos usuários com permissão de login
CREATE USER usuario_dba         WITH LOGIN PASSWORD 'senha_dba123';
CREATE USER usuario_cliente     WITH LOGIN PASSWORD 'senha_cliente123';
CREATE USER usuario_restaurante WITH LOGIN PASSWORD 'senha_rest456';
CREATE USER usuario_entregador  WITH LOGIN PASSWORD 'senha_ent789';

-- Associação dos usuários às suas respectivas roles
GRANT role_dba         TO usuario_dba;
GRANT role_cliente     TO usuario_cliente;
GRANT role_restaurante TO usuario_restaurante;
GRANT role_entregador  TO usuario_entregador;

-- O schema "public" já existe por padrão em todo banco novo do Postgres,
-- mas o comando abaixo garante que ele exista mesmo que tenha sido removido.
CREATE SCHEMA IF NOT EXISTS public;

-- ================================================================
-- ▌ PARTE 1 — SCHEMA (Estrutura do banco)
-- ================================================================

-- Tipos de cadastro, perfis, status e domínios
CREATE TABLE tipo_cadastro (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(2)  NOT NULL
);

CREATE TABLE tipo_pessoa (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(20) NOT NULL
);

CREATE TABLE status_de_pedido (
    id      SERIAL      PRIMARY KEY,
    status  VARCHAR(20) NOT NULL
);

CREATE TABLE metodo_pagamento (
    id      SERIAL      PRIMARY KEY,
    metodo  VARCHAR(20) NOT NULL
);

CREATE TABLE status_pagamento (
    id      SERIAL      PRIMARY KEY,
    status  VARCHAR(10) NOT NULL
);

CREATE TABLE estado (
    id      SERIAL      PRIMARY KEY,
    nome    VARCHAR(50) NOT NULL
);

CREATE TABLE tipo_logradouro (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(15) NOT NULL
);

CREATE TABLE tipo_cozinha (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(30) NOT NULL
);

CREATE TABLE cidade (
    id          SERIAL          PRIMARY KEY,
    nome        VARCHAR(100)    NOT NULL,
    estado_id   INTEGER         NOT NULL REFERENCES estado(id)
);

CREATE TABLE pessoa (
    pessoa_id       SERIAL          PRIMARY KEY,
    cpf_cnpj        VARCHAR(14)     UNIQUE,
    nome            VARCHAR(100)    NOT NULL,
    login_usuario   VARCHAR(50)     UNIQUE,
    tipo_cadastro   INTEGER         NOT NULL REFERENCES tipo_cadastro(id),
    tipo_pessoa_id  INTEGER         NOT NULL REFERENCES tipo_pessoa(id),
    CONSTRAINT chk_cpf_cnpj_tamanho CHECK (LENGTH(cpf_cnpj) IN (11, 14))
);

CREATE TABLE endereco (
    id_endereco         SERIAL          PRIMARY KEY,
    id_pessoa           INTEGER         NOT NULL REFERENCES pessoa(pessoa_id),
    cep                 VARCHAR(9),
    tipo_logradouro_id  INTEGER         REFERENCES tipo_logradouro(id),
    logradouro          VARCHAR(100),
    cidade_id           INTEGER         NOT NULL REFERENCES cidade(id),
    numero              INTEGER,
    bairro              VARCHAR(60),
    tipo_endereco       VARCHAR(20),
    latitude            DECIMAL,
    longitude           DECIMAL
);

CREATE TABLE restaurante (
    id                      SERIAL          PRIMARY KEY,
    pessoa_id               INTEGER         NOT NULL REFERENCES pessoa(pessoa_id),
    nome                    VARCHAR(100)    NOT NULL,
    status_funcionamento    BOOLEAN         NOT NULL DEFAULT FALSE,
    tipo_cozinha_id         INTEGER         NOT NULL REFERENCES tipo_cozinha(id)
);

CREATE TABLE produto (
    id              SERIAL          PRIMARY KEY,
    nome            VARCHAR(100)    NOT NULL,
    tipo            VARCHAR(30),
    preco           FLOAT4,
    custo           FLOAT4,
    restaurante_id  INTEGER         NOT NULL REFERENCES restaurante(id)
);

CREATE TABLE colaboradores (
    id              SERIAL          PRIMARY KEY,
    pessoa_id       INTEGER         NOT NULL REFERENCES pessoa(pessoa_id),
    restaurante_id  INTEGER         NOT NULL REFERENCES restaurante(id),
    cargo           VARCHAR(50),
    salario         FLOAT4
);

CREATE TABLE entregador (
    id          SERIAL      PRIMARY KEY,
    pessoa_id   INTEGER     NOT NULL REFERENCES pessoa(pessoa_id),
    disponivel  BOOLEAN     NOT NULL DEFAULT FALSE,
    latitude    NUMERIC,
    longitude   NUMERIC
);

CREATE TABLE pedido (
    id              SERIAL      PRIMARY KEY,
    cliente_id      INTEGER     NOT NULL REFERENCES pessoa(pessoa_id),
    restaurante_id  INTEGER     NOT NULL REFERENCES restaurante(id),
    entregador_id   INTEGER     REFERENCES entregador(id),
    status          INTEGER     NOT NULL REFERENCES status_de_pedido(id),
    data_hora       TIMESTAMP,
    taxa_entrega    FLOAT4,
    valor_total     FLOAT4
);

CREATE TABLE pedido_itens (
    id              SERIAL  PRIMARY KEY,
    pedido_id       INTEGER NOT NULL REFERENCES pedido(id),
    produto_id      INTEGER NOT NULL REFERENCES produto(id),
    quantidade      INTEGER NOT NULL,
    mongodb_item_id VARCHAR(24)
);

CREATE TABLE pagamento (
    id          SERIAL  PRIMARY KEY,
    pedido_id   INTEGER NOT NULL REFERENCES pedido(id),
    metodo_id   INTEGER NOT NULL REFERENCES metodo_pagamento(id),
    status_id   INTEGER NOT NULL REFERENCES status_pagamento(id)
);

CREATE TABLE historico_pedido (
    id                  SERIAL      PRIMARY KEY,
    pedido_id           INTEGER     NOT NULL REFERENCES pedido(id),
    status_anterior_id  INTEGER     NOT NULL REFERENCES status_de_pedido(id),
    status_novo_id      INTEGER     NOT NULL REFERENCES status_de_pedido(id),
    data_alteracao      TIMESTAMP   NOT NULL DEFAULT NOW()
);

-- Seeds obrigatórios
INSERT INTO tipo_cadastro (tipo) VALUES ('PF'), ('PJ');
INSERT INTO tipo_pessoa (tipo) VALUES ('Cliente'), ('Restaurante'), ('Entregador');

INSERT INTO tipo_logradouro (tipo) VALUES
    ('Rua'), ('Avenida'), ('Alameda'), ('Travessa'), ('Estrada'),
    ('Rodovia'), ('Praça'), ('Largo'), ('Viela'), ('Beco'),
    ('Quadra'), ('Setor'), ('Condomínio'), ('Fazenda'), ('Sítio');

INSERT INTO status_de_pedido (status) VALUES
    ('Pendente'), ('Aceito'), ('Em preparo'), ('Saiu para entrega'), ('Entregue');

INSERT INTO metodo_pagamento (metodo) VALUES
    ('Cartão de Crédito'), ('Cartão de Débito'), ('Pix');

INSERT INTO status_pagamento (status) VALUES ('Pendente'), ('Pago');

INSERT INTO tipo_cozinha (tipo) VALUES
    ('Pizzaria'), ('Hamburgueria'), ('Japonês / Sushi'), ('Churrascaria'),
    ('Italiana'), ('Mexicana'), ('Árabe / Mediterrânea'), ('Chinesa'),
    ('Brasileira'), ('Vegetariana / Vegana'), ('Frutos do Mar / Peixaria'),
    ('Cafeteria'), ('Padaria / Confeitaria'), ('Fast Food'), ('Lanchonete'),
    ('Sorvetes e Açaí'), ('Peruana'), ('Contemporânea / Bistrô');


-- ================================================================
-- ▌ PARTE 2 — PROCEDURES, TRIGGERS E VIEWS
-- ================================================================

CREATE OR REPLACE PROCEDURE calcular_taxa_entrega(
    IN  p_distancia_km  FLOAT,
    OUT p_taxa          FLOAT
)
LANGUAGE plpgsql
AS $$
BEGIN
    p_taxa := 3.00 + (p_distancia_km * 1.50);
END;
$$;

CREATE OR REPLACE PROCEDURE atribuir_entregador(
    IN p_pedido_id INTEGER
)
LANGUAGE plpgsql
AS $$
DECLARE
    v_restaurante_lat   NUMERIC;
    v_restaurante_lon   NUMERIC;
    v_entregador_id     INTEGER;
    v_entregador_lat    NUMERIC;
    v_entregador_lon    NUMERIC;
    v_melhor_id         INTEGER := NULL;
    v_menor_distancia   FLOAT   := 999999;
    v_distancia_atual   FLOAT;
    cur_entregadores CURSOR FOR
        SELECT id, latitude, longitude
        FROM entregador
        WHERE disponivel = TRUE;
BEGIN
    SELECT e.latitude, e.longitude
    INTO v_restaurante_lat, v_restaurante_lon
    FROM pedido p
    JOIN restaurante r ON r.id = p.restaurante_id
    JOIN endereco e    ON e.id_pessoa = r.pessoa_id
    WHERE p.id = p_pedido_id
    LIMIT 1;

    OPEN cur_entregadores;
    LOOP
        FETCH cur_entregadores INTO v_entregador_id, v_entregador_lat, v_entregador_lon;
        EXIT WHEN NOT FOUND;

        v_distancia_atual := SQRT(
            POWER(v_entregador_lat - v_restaurante_lat, 2) +
            POWER(v_entregador_lon - v_restaurante_lon, 2)
        );

        IF v_distancia_atual < v_menor_distancia THEN
            v_menor_distancia := v_distancia_atual;
            v_melhor_id       := v_entregador_id;
        END IF;
    END LOOP;
    CLOSE cur_entregadores;

    IF v_melhor_id IS NOT NULL THEN
        UPDATE pedido SET entregador_id = v_melhor_id WHERE id = p_pedido_id;
    END IF;
END;
$$;

CREATE OR REPLACE FUNCTION fn_registrar_historico_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    IF OLD.status <> NEW.status THEN
        INSERT INTO historico_pedido (pedido_id, status_anterior_id, status_novo_id, data_alteracao)
        VALUES (OLD.id, OLD.status, NEW.status, NOW());
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_historico_pedido
AFTER UPDATE ON pedido
FOR EACH ROW
EXECUTE FUNCTION fn_registrar_historico_pedido();

CREATE OR REPLACE FUNCTION fn_bloquear_restaurante_fechado()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
DECLARE
    v_funcionando BOOLEAN;
BEGIN
    SELECT status_funcionamento INTO v_funcionando
    FROM restaurante WHERE id = NEW.restaurante_id;

    IF v_funcionando = FALSE THEN
        RAISE EXCEPTION 'Não é possível atualizar o pedido: o restaurante está fechado.';
    END IF;

    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_bloquear_restaurante_fechado
BEFORE INSERT OR UPDATE ON pedido
FOR EACH ROW
EXECUTE FUNCTION fn_bloquear_restaurante_fechado();

CREATE OR REPLACE VIEW cardapio_online AS
SELECT
    id,
    nome,
    tipo,
    preco,
    restaurante_id
FROM produto;

CREATE MATERIALIZED VIEW desempenho_entregadores AS
SELECT
    e.id                    AS entregador_id,
    p.nome                  AS nome_entregador,
    COUNT(ped.id)           AS total_entregas,
    AVG(ped.taxa_entrega)   AS media_taxa_entrega
FROM entregador e
JOIN pessoa p       ON p.pessoa_id = e.pessoa_id
LEFT JOIN pedido ped ON ped.entregador_id = e.id
GROUP BY e.id, p.nome;

CREATE OR REPLACE FUNCTION fn_pessoa_id_do_usuario()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT pessoa_id
    FROM pessoa
    WHERE login_usuario = current_user
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_restaurante_id_do_usuario()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT r.id
    FROM restaurante r
    JOIN pessoa p ON p.pessoa_id = r.pessoa_id
    WHERE p.login_usuario = current_user
    LIMIT 1;
$$;

CREATE OR REPLACE FUNCTION fn_entregador_id_do_usuario()
RETURNS INTEGER
LANGUAGE sql
SECURITY DEFINER
AS $$
    SELECT e.id
    FROM entregador e
    JOIN pessoa p ON p.pessoa_id = e.pessoa_id
    WHERE p.login_usuario = current_user
    LIMIT 1;
$$;


-- ================================================================
-- ▌ PARTE 5 — SEGURANÇA
-- ================================================================

-- Garante acesso administrativo aos objetos já existentes.
GRANT ALL PRIVILEGES ON ALL TABLES IN SCHEMA public TO role_dba;
GRANT ALL PRIVILEGES ON ALL SEQUENCES IN SCHEMA public TO role_dba;
GRANT ALL PRIVILEGES ON ALL FUNCTIONS IN SCHEMA public TO role_dba;


GRANT SELECT ON cardapio_online TO role_cliente;
GRANT INSERT ON pedido          TO role_cliente;
GRANT USAGE, SELECT ON SEQUENCE pedido_id_seq TO role_cliente;
GRANT SELECT ON pedido          TO role_cliente;
GRANT SELECT, INSERT ON pedido_itens TO role_cliente;
GRANT USAGE, SELECT ON SEQUENCE pedido_itens_id_seq TO role_cliente;
GRANT SELECT ON metodo_pagamento TO role_cliente;
GRANT SELECT ON status_de_pedido TO role_cliente;
GRANT SELECT ON status_pagamento  TO role_cliente;
GRANT INSERT ON pagamento TO role_cliente;
GRANT USAGE, SELECT ON SEQUENCE pagamento_id_seq TO role_cliente;

GRANT SELECT, INSERT, UPDATE, DELETE ON produto TO role_restaurante;
GRANT USAGE, SELECT ON SEQUENCE produto_id_seq TO role_restaurante;
GRANT SELECT, UPDATE ON pedido          TO role_restaurante;
GRANT SELECT         ON pedido_itens    TO role_restaurante;
GRANT SELECT         ON historico_pedido TO role_restaurante;
GRANT SELECT         ON status_de_pedido TO role_restaurante;

GRANT SELECT ON pedido          TO role_entregador;
GRANT UPDATE (status)           ON pedido     TO role_entregador;
GRANT UPDATE (disponivel, latitude, longitude) ON entregador TO role_entregador;
GRANT SELECT ON entregador      TO role_entregador;
GRANT SELECT ON status_de_pedido TO role_entregador;

REVOKE ALL ON produto       FROM PUBLIC;
REVOKE ALL ON pessoa        FROM PUBLIC;
REVOKE ALL ON colaboradores FROM PUBLIC;
REVOKE ALL ON pagamento     FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON produto   TO role_restaurante;
GRANT INSERT, SELECT                 ON pagamento TO role_cliente;
GRANT SELECT                         ON pagamento TO role_restaurante;


ALTER TABLE pedido ENABLE ROW LEVEL SECURITY;

-- Remove as políticas antigas se existirem para evitar conflitos ao reexecutar
DROP POLICY IF EXISTS politica_cliente_pedido ON pedido;
DROP POLICY IF EXISTS politica_restaurante_pedido ON pedido;
DROP POLICY IF EXISTS politica_entregador_pedido ON pedido;
DROP POLICY IF EXISTS politica_cliente_pedido_select ON pedido;
DROP POLICY IF EXISTS politica_cliente_pedido_insert ON pedido;
DROP POLICY IF EXISTS politica_cliente_pedido_update ON pedido;
DROP POLICY IF EXISTS politica_restaurante_pedido_select ON pedido;
DROP POLICY IF EXISTS politica_restaurante_pedido_update ON pedido;
DROP POLICY IF EXISTS politica_entregador_pedido_select ON pedido;
DROP POLICY IF EXISTS politica_entregador_pedido_update ON pedido;

-- Políticas para Cliente
CREATE POLICY politica_cliente_pedido_select
    ON pedido FOR SELECT TO role_cliente
    USING (cliente_id = fn_pessoa_id_do_usuario());

CREATE POLICY politica_cliente_pedido_insert
    ON pedido FOR INSERT TO role_cliente
    WITH CHECK (cliente_id = fn_pessoa_id_do_usuario());

CREATE POLICY politica_cliente_pedido_update
    ON pedido FOR UPDATE TO role_cliente
    USING (cliente_id = fn_pessoa_id_do_usuario())
    WITH CHECK (cliente_id = fn_pessoa_id_do_usuario());

-- Políticas para Restaurante
CREATE POLICY politica_restaurante_pedido_select
    ON pedido FOR SELECT TO role_restaurante
    USING (restaurante_id = fn_restaurante_id_do_usuario());

CREATE POLICY politica_restaurante_pedido_update
    ON pedido FOR UPDATE TO role_restaurante
    USING (restaurante_id = fn_restaurante_id_do_usuario())
    WITH CHECK (restaurante_id = fn_restaurante_id_do_usuario());

-- Políticas para Entregador
CREATE POLICY politica_entregador_pedido_select
    ON pedido FOR SELECT TO role_entregador
    USING (entregador_id = fn_entregador_id_do_usuario());

CREATE POLICY politica_entregador_pedido_update
    ON pedido FOR UPDATE TO role_entregador
    USING (entregador_id = fn_entregador_id_do_usuario())
    WITH CHECK (entregador_id = fn_entregador_id_do_usuario());


-- ================================================================
-- ▌ PARTE 6 — ÍNDICES E OTIMIZAÇÃO
-- ================================================================

CREATE INDEX IF NOT EXISTS idx_produto_tipo
    ON produto (tipo);

CREATE INDEX IF NOT EXISTS idx_restaurante_tipo_cozinha
    ON restaurante (tipo_cozinha_id);

CREATE INDEX IF NOT EXISTS idx_endereco_cep
    ON endereco (cep);

CREATE INDEX IF NOT EXISTS idx_endereco_coordenadas
    ON endereco (latitude, longitude);

CREATE INDEX IF NOT EXISTS idx_pedido_status
    ON pedido (status);

CREATE INDEX IF NOT EXISTS idx_pedido_cliente
    ON pedido (cliente_id);

CREATE INDEX IF NOT EXISTS idx_pedido_restaurante
    ON pedido (restaurante_id);

CREATE INDEX IF NOT EXISTS idx_restaurante_status
    ON restaurante (status_funcionamento);

CREATE INDEX IF NOT EXISTS idx_entregador_disponivel
    ON entregador (disponivel);

CREATE UNIQUE INDEX IF NOT EXISTS idx_desempenho_entregador_id
    ON desempenho_entregadores (entregador_id);

REFRESH MATERIALIZED VIEW CONCURRENTLY desempenho_entregadores;