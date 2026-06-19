-- ============================================================
--  SISTEMA DE DELIVERY — BANCO DE DADOS II
--  Script unificado para apresentação
--
--  ORDEM DE EXECUÇÃO:
--    1. SCHEMA         → cria tabelas e insere dados iniciais
--    2. EXTRAS         → procedures, triggers e views
--    3. DML            → inserts, updates e transações
--    4. SQL AVANÇADO   → subqueries, CTEs e window functions
--    5. SEGURANÇA      → roles, grants e row level security
--    6. ÍNDICES        → criação, justificativa e análise
-- ============================================================




-- ================================================================
-- ▌ PARTE 1 — SCHEMA (Estrutura do banco)
-- ================================================================
--
--  Aqui definimos todas as tabelas do sistema.
--  A ordem importa: tabelas sem dependências vêm primeiro,
--  depois as que referenciam outras (chaves estrangeiras).
--
--  Hierarquia de dependências:
--    tipo_cadastro, tipo_pessoa, status_de_pedido,
--    metodo_pagamento, status_pagamento, estado
--        ↓
--    cidade, pessoa
--        ↓
--    endereco, restaurante, entregador
--        ↓
--    produto, colaboradores
--        ↓
--    pedido
--        ↓
--    pedido_itens, pagamento, historico_pedido
-- ================================================================


-- ── Tabelas de domínio (sem dependências) ────────────────────────

-- Tipos: PF ou PJ
CREATE TABLE tipo_cadastro (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(2)  NOT NULL      -- só guarda 'PF' ou 'PJ'
);

-- Perfis: Cliente, Restaurante, Entregador
CREATE TABLE tipo_pessoa (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(20) NOT NULL
);

-- Ciclo de vida do pedido: Pendente → Aceito → Em preparo → Saiu → Entregue
CREATE TABLE status_de_pedido (
    id      SERIAL      PRIMARY KEY,
    status  VARCHAR(20) NOT NULL      -- cobre "Saiu para entrega" (18 chars)
);

-- Formas de pagamento aceitas
CREATE TABLE metodo_pagamento (
    id      SERIAL      PRIMARY KEY,
    metodo  VARCHAR(20) NOT NULL      -- cobre "Cartão de Crédito" (17 chars)
);

-- Situação do pagamento: Pendente ou Pago
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
    tipo    VARCHAR(15) NOT NULL      -- cobre "Condomínio" (10 chars)
);

-- Tipo de cozinha do restaurante (Pizzaria, Japonesa, etc.)
CREATE TABLE tipo_cozinha (
    id      SERIAL      PRIMARY KEY,
    tipo    VARCHAR(30) NOT NULL      -- cobre "Frutos do Mar / Peixaria" (24 chars)
);


-- ── Cidade (depende de estado) ────────────────────────────────────

CREATE TABLE cidade (
    id          SERIAL          PRIMARY KEY,
    nome        VARCHAR(100)    NOT NULL,
    estado_id   INTEGER         NOT NULL REFERENCES estado(id)
);


-- ── Pessoa (entidade central do sistema) ─────────────────────────
--
--  Uma mesma tabela guarda clientes, donos de restaurante
--  e entregadores — diferenciados por tipo_pessoa_id.
--  pessoa_id é um SERIAL para gerar identificadores automáticos.
--
--  cpf_cnpj é salvo SEM máscara (só números):
--    CPF  → 11 dígitos
--    CNPJ → 14 dígitos
--  O CHECK abaixo garante que o tamanho bate com o tipo_cadastro
--  (PF deve ter 11 dígitos, PJ deve ter 14).

CREATE TABLE pessoa (
    pessoa_id       SERIAL          PRIMARY KEY,
    cpf_cnpj        VARCHAR(14)     UNIQUE,         -- só números: 11 (CPF) ou 14 (CNPJ)
    nome            VARCHAR(100)    NOT NULL,
    tipo_cadastro   INTEGER         NOT NULL REFERENCES tipo_cadastro(id),
    tipo_pessoa_id  INTEGER         NOT NULL REFERENCES tipo_pessoa(id),
    CONSTRAINT chk_cpf_cnpj_tamanho CHECK (LENGTH(cpf_cnpj) IN (11, 14))
);


-- ── Endereço (depende de pessoa e cidade) ────────────────────────
--
--  latitude e longitude são usadas pela procedure
--  atribuir_entregador para calcular distâncias.

CREATE TABLE endereco (
    id_endereco         SERIAL          PRIMARY KEY,
    id_pessoa           INTEGER         NOT NULL REFERENCES pessoa(pessoa_id),
    cep                 VARCHAR(9),                 -- 00000-000
    tipo_logradouro_id  INTEGER         REFERENCES tipo_logradouro(id),
    logradouro          VARCHAR(100),
    cidade_id           INTEGER         NOT NULL REFERENCES cidade(id),
    numero              INTEGER,
    bairro              VARCHAR(60),
    tipo_endereco       VARCHAR(20),
    latitude            DECIMAL,
    longitude           DECIMAL
);


-- ── Restaurante ───────────────────────────────────────────────────
--
--  status_funcionamento é verificado pela trigger
--  trg_bloquear_restaurante_fechado antes de cada pedido.
--  tipo_cozinha_id classifica o restaurante (Pizzaria, Japonesa, etc).

CREATE TABLE restaurante (
    id                      SERIAL          PRIMARY KEY,
    pessoa_id               INTEGER         NOT NULL REFERENCES pessoa(pessoa_id),
    nome                    VARCHAR(100)    NOT NULL,
    status_funcionamento    BOOLEAN         NOT NULL DEFAULT FALSE,
    tipo_cozinha_id         INTEGER         NOT NULL REFERENCES tipo_cozinha(id)
);


-- ── Produto ───────────────────────────────────────────────────────
--
--  A coluna "custo" é sensível — clientes não devem vê-la.
--  Por isso criamos a view cardapio_online que a omite.

CREATE TABLE produto (
    id              SERIAL          PRIMARY KEY,
    nome            VARCHAR(100)    NOT NULL,
    tipo            VARCHAR(30),
    preco           FLOAT4,
    custo           FLOAT4,          -- ← coluna protegida (não exposta ao cliente)
    restaurante_id  INTEGER         NOT NULL REFERENCES restaurante(id)
);


-- ── Colaboradores ─────────────────────────────────────────────────

CREATE TABLE colaboradores (
    id              SERIAL          PRIMARY KEY,
    pessoa_id       INTEGER         NOT NULL REFERENCES pessoa(pessoa_id),
    restaurante_id  INTEGER         NOT NULL REFERENCES restaurante(id),
    cargo           VARCHAR(50),
    salario         FLOAT4           -- ← dado sensível, protegido por REVOKE
);


-- ── Entregador ────────────────────────────────────────────────────
--
--  latitude e longitude registram a posição atual do entregador.
--  Usados pela procedure atribuir_entregador para encontrar
--  o mais próximo do restaurante.

CREATE TABLE entregador (
    id          SERIAL      PRIMARY KEY,
    pessoa_id   INTEGER     NOT NULL REFERENCES pessoa(pessoa_id),
    disponivel  BOOLEAN     NOT NULL DEFAULT FALSE,
    latitude    NUMERIC,
    longitude   NUMERIC
);


-- ── Pedido ────────────────────────────────────────────────────────
--
--  Tabela central: conecta cliente, restaurante e entregador.
--  entregador_id pode ser NULL (preenchido depois pela procedure).
--  Alterações no campo "status" disparam a trigger de histórico.

CREATE TABLE pedido (
    id              SERIAL      PRIMARY KEY,
    cliente_id      INTEGER     NOT NULL REFERENCES pessoa(pessoa_id),
    restaurante_id  INTEGER     NOT NULL REFERENCES restaurante(id),
    entregador_id   INTEGER     REFERENCES entregador(id),   -- nullable: atribuído depois
    status          INTEGER     NOT NULL REFERENCES status_de_pedido(id),
    data_hora       TIMESTAMP,
    taxa_entrega    FLOAT4,
    valor_total     FLOAT4
);


-- ── Pedido Itens ──────────────────────────────────────────────────

CREATE TABLE pedido_itens (
    id          SERIAL  PRIMARY KEY,
    pedido_id   INTEGER NOT NULL REFERENCES pedido(id),
    produto_id  INTEGER NOT NULL REFERENCES produto(id),
    quantidade  INTEGER NOT NULL
);


-- ── Pagamento ─────────────────────────────────────────────────────

CREATE TABLE pagamento (
    id          SERIAL  PRIMARY KEY,
    pedido_id   INTEGER NOT NULL REFERENCES pedido(id),
    metodo_id   INTEGER NOT NULL REFERENCES metodo_pagamento(id),
    status_id   INTEGER NOT NULL REFERENCES status_pagamento(id)
);


-- ── Histórico de Pedido ───────────────────────────────────────────
--
--  Preenchida AUTOMATICAMENTE pela trigger trg_historico_pedido.
--  Nunca inserimos aqui manualmente — a trigger faz isso.

CREATE TABLE historico_pedido (
    id                  SERIAL      PRIMARY KEY,
    pedido_id           INTEGER     NOT NULL REFERENCES pedido(id),
    status_anterior_id  INTEGER     NOT NULL REFERENCES status_de_pedido(id),
    status_novo_id      INTEGER     NOT NULL REFERENCES status_de_pedido(id),
    data_alteracao      TIMESTAMP   NOT NULL DEFAULT NOW()
);


-- ── Seeds (dados iniciais obrigatórios) ──────────────────────────

INSERT INTO tipo_cadastro (tipo) VALUES ('PF'), ('PJ');

INSERT INTO tipo_pessoa (tipo) VALUES ('Cliente'), ('Restaurante'), ('Entregador');

INSERT INTO tipo_logradouro (tipo) VALUES
    ('Rua'), ('Avenida'), ('Alameda'), ('Travessa'), ('Estrada'),
    ('Rodovia'), ('Praça'), ('Largo'), ('Viela'), ('Beco'),
    ('Quadra'), ('Setor'), ('Condomínio'), ('Fazenda'), ('Sítio');

-- Status do ciclo de vida do pedido (ordem importa para a lógica)
INSERT INTO status_de_pedido (status) VALUES
    ('Pendente'), ('Aceito'), ('Em preparo'), ('Saiu para entrega'), ('Entregue');

INSERT INTO metodo_pagamento (metodo) VALUES
    ('Cartão de Crédito'), ('Cartão de Débito'), ('Pix');

INSERT INTO status_pagamento (status) VALUES ('Pendente'), ('Pago');

-- Tipos de cozinha do restaurante
INSERT INTO tipo_cozinha (tipo) VALUES
    ('Pizzaria'), ('Hamburgueria'), ('Japonês / Sushi'), ('Churrascaria'),
    ('Italiana'), ('Mexicana'), ('Árabe / Mediterrânea'), ('Chinesa'),
    ('Brasileira'), ('Vegetariana / Vegana'), ('Frutos do Mar / Peixaria'),
    ('Cafeteria'), ('Padaria / Confeitaria'), ('Fast Food'), ('Lanchonete'),
    ('Sorvetes e Açaí'), ('Peruana'), ('Contemporânea / Bistrô');




-- ================================================================
-- ▌ PARTE 2 — PROCEDURES, TRIGGERS E VIEWS
-- ================================================================
--
--  Objetos que encapsulam regras de negócio dentro do próprio banco.
--  Vantagem: funcionam independente da linguagem da aplicação.
-- ================================================================


-- ── Procedure 1: calcular_taxa_entrega ───────────────────────────
--
--  CONCEITO DE IN/OUT:
--    IN  → dado que a procedure RECEBE (entrada)
--    OUT → dado que a procedure DEVOLVE (saída), como um retorno
--
--  Regra de negócio: R$ 3,00 fixo + R$ 1,50 por km percorrido.
--  Chamada: CALL calcular_taxa_entrega(5.0, NULL);
--           O NULL é preenchido automaticamente com o resultado.

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


-- ── Procedure 2: atribuir_entregador ─────────────────────────────
--
--  CONCEITO DE CURSOR:
--    Um cursor percorre linhas de um SELECT uma a uma,
--    como um ponteiro que avança pela tabela.
--    Útil quando precisamos processar cada linha com lógica
--    que não é possível expressar só com SQL puro.
--
--  Lógica:
--    1. Busca lat/lon do restaurante do pedido
--    2. Cursor percorre todos os entregadores disponíveis
--    3. Para cada um, calcula a distância euclidiana
--    4. Salva o mais próximo e atribui ao pedido

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
    v_menor_distancia   FLOAT   := 999999;  -- inicia alto para qualquer distância ser menor
    v_distancia_atual   FLOAT;

    -- Cursor busca apenas entregadores disponíveis
    cur_entregadores CURSOR FOR
        SELECT id, latitude, longitude
        FROM entregador
        WHERE disponivel = TRUE;
BEGIN
    -- Passo 1: coordenadas do restaurante (via endereço do dono)
    SELECT e.latitude, e.longitude
    INTO v_restaurante_lat, v_restaurante_lon
    FROM pedido p
    JOIN restaurante r ON r.id = p.restaurante_id
    JOIN endereco e    ON e.id_pessoa = r.pessoa_id
    WHERE p.id = p_pedido_id
    LIMIT 1;

    -- Passo 2: percorre cada entregador disponível com o cursor
    OPEN cur_entregadores;
    LOOP
        FETCH cur_entregadores INTO v_entregador_id, v_entregador_lat, v_entregador_lon;
        EXIT WHEN NOT FOUND;  -- sai do loop quando não há mais linhas

        -- Passo 3: fórmula euclidiana (simplificação da distância real)
        v_distancia_atual := SQRT(
            POWER(v_entregador_lat - v_restaurante_lat, 2) +
            POWER(v_entregador_lon - v_restaurante_lon, 2)
        );

        -- Passo 4: guarda o mais próximo encontrado até agora
        IF v_distancia_atual < v_menor_distancia THEN
            v_menor_distancia := v_distancia_atual;
            v_melhor_id       := v_entregador_id;
        END IF;
    END LOOP;
    CLOSE cur_entregadores;

    -- Passo 5: atribui ao pedido
    IF v_melhor_id IS NOT NULL THEN
        UPDATE pedido SET entregador_id = v_melhor_id WHERE id = p_pedido_id;
        RAISE NOTICE 'Entregador % atribuído ao pedido %.', v_melhor_id, p_pedido_id;
    ELSE
        RAISE NOTICE 'Nenhum entregador disponível.';
    END IF;
END;
$$;


-- ── Trigger 1: histórico automático de status ────────────────────
--
--  CONCEITO DE TRIGGER:
--    É uma função executada automaticamente pelo banco
--    quando um evento ocorre (INSERT, UPDATE, DELETE).
--    AFTER UPDATE → dispara DEPOIS que o UPDATE acontece.
--    FOR EACH ROW → executa uma vez por linha alterada.
--
--  OLD = linha antes do UPDATE
--  NEW = linha depois do UPDATE
--
--  Toda vez que o campo "status" de um pedido mudar,
--  o banco grava o registro em historico_pedido sozinho.

CREATE OR REPLACE FUNCTION fn_registrar_historico_pedido()
RETURNS TRIGGER
LANGUAGE plpgsql
AS $$
BEGIN
    -- Só registra se o status realmente mudou (evita registros desnecessários)
    IF OLD.status <> NEW.status THEN
        INSERT INTO historico_pedido (pedido_id, status_anterior_id, status_novo_id, data_alteracao)
        VALUES (OLD.id, OLD.status, NEW.status, NOW());
    END IF;
    RETURN NEW;
END;
$$;

CREATE TRIGGER trg_historico_pedido
AFTER UPDATE ON pedido       -- dispara após qualquer UPDATE na tabela pedido
FOR EACH ROW                 -- uma vez por linha alterada
EXECUTE FUNCTION fn_registrar_historico_pedido();


-- ── Trigger 2: bloquear pedido em restaurante fechado ────────────
--
--  BEFORE INSERT → dispara ANTES de inserir o pedido.
--  Se o restaurante estiver fechado, lança EXCEPTION
--  e o INSERT é cancelado automaticamente.
--
--  Diferença de AFTER: BEFORE pode impedir a operação.
--  AFTER apenas reage a ela depois que já aconteceu.

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
        -- RAISE EXCEPTION cancela o INSERT e desfaz a transação
        RAISE EXCEPTION 'Não é possível criar pedido: o restaurante está fechado.';
    END IF;

    RETURN NEW;  -- permite o INSERT prosseguir
END;
$$;

CREATE TRIGGER trg_bloquear_restaurante_fechado
BEFORE INSERT ON pedido
FOR EACH ROW
EXECUTE FUNCTION fn_bloquear_restaurante_fechado();


-- ── View simples: cardapio_online ─────────────────────────────────
--
--  CONCEITO DE VIEW:
--    Uma consulta salva com nome, acessada como se fosse uma tabela.
--    Aqui usamos para OCULTAR a coluna "custo" dos clientes.
--    O cliente faz SELECT * FROM cardapio_online e nunca vê o custo.

CREATE OR REPLACE VIEW cardapio_online AS
SELECT
    id,
    nome,
    tipo,
    preco,
    restaurante_id
    -- "custo" foi intencionalmente omitido
FROM produto;


-- ── View materializada: desempenho_entregadores ──────────────────
--
--  CONCEITO DE VIEW MATERIALIZADA:
--    Diferente da view comum (que executa a query a cada acesso),
--    a materializada SALVA o resultado em disco.
--    Leitura muito mais rápida — ideal para relatórios.
--    Desvantagem: dados ficam "congelados" até o próximo REFRESH.
--
--  REFRESH MATERIALIZED VIEW CONCURRENTLY → atualiza sem bloquear
--  leituras simultâneas (exige índice único — criado na Parte 6).

CREATE MATERIALIZED VIEW desempenho_entregadores AS
SELECT
    e.id                    AS entregador_id,
    p.nome                  AS nome_entregador,
    COUNT(ped.id)           AS total_entregas,
    AVG(ped.taxa_entrega)   AS media_taxa_entrega
FROM entregador e
JOIN pessoa p       ON p.pessoa_id = e.pessoa_id
LEFT JOIN pedido ped ON ped.entregador_id = e.id  -- LEFT JOIN para incluir quem não entregou nada
GROUP BY e.id, p.nome;

-- Para atualizar os dados sem bloquear o banco:
-- REFRESH MATERIALIZED VIEW CONCURRENTLY desempenho_entregadores;




-- ================================================================
-- ▌ PARTE 3 — DML E TRANSAÇÕES
-- ================================================================
--
--  CONCEITO DE TRANSAÇÃO:
--    Conjunto de operações que se comporta como uma unidade.
--    Ou tudo é confirmado (COMMIT), ou tudo é desfeito (ROLLBACK).
--
--    BEGIN      → inicia a transação
--    COMMIT     → salva tudo definitivamente
--    ROLLBACK   → desfaz tudo desde o BEGIN
--    SAVEPOINT  → ponto de restauração parcial dentro da transação
--
--  Por que usar SAVEPOINT?
--    Ao criar um pedido temos duas etapas: inserir o pedido
--    e inserir os itens. Com SAVEPOINT podemos desfazer
--    só os itens se falharem, sem perder o pedido inteiro.
-- ================================================================


-- ── Bloco 1: inserção dos dados de teste ─────────────────────────
--
--  ON CONFLICT DO NOTHING → se o registro já existir, ignora.
--  Permite rodar o script múltiplas vezes sem erro de duplicata.

DO $$
BEGIN
    INSERT INTO estado (nome) VALUES ('Santa Catarina')
    ON CONFLICT DO NOTHING;

    INSERT INTO cidade (nome, estado_id)
    SELECT 'Canoinhas', id FROM estado WHERE nome = 'Santa Catarina'
    ON CONFLICT DO NOTHING;

    -- Cliente
    INSERT INTO pessoa (cpf_cnpj, nome, tipo_cadastro, tipo_pessoa_id)
    VALUES (
        '11111111111', 'Ana Souza',
        (SELECT id FROM tipo_cadastro WHERE tipo = 'PF'),
        (SELECT id FROM tipo_pessoa   WHERE tipo = 'Cliente')
    ) ON CONFLICT DO NOTHING;

    -- Dono do restaurante (PJ)
    INSERT INTO pessoa (cpf_cnpj, nome, tipo_cadastro, tipo_pessoa_id)
    VALUES (
        '22222222000122', 'Pizzaria do João LTDA',
        (SELECT id FROM tipo_cadastro WHERE tipo = 'PJ'),
        (SELECT id FROM tipo_pessoa   WHERE tipo = 'Restaurante')
    ) ON CONFLICT DO NOTHING;

    -- Entregador
    INSERT INTO pessoa (cpf_cnpj, nome, tipo_cadastro, tipo_pessoa_id)
    VALUES (
        '33333333333', 'Carlos Moto',
        (SELECT id FROM tipo_cadastro WHERE tipo = 'PF'),
        (SELECT id FROM tipo_pessoa   WHERE tipo = 'Entregador')
    ) ON CONFLICT DO NOTHING;

    -- Endereço do cliente (com coordenadas para a procedure de distância)
    INSERT INTO endereco (id_pessoa, cep, logradouro, cidade_id, numero, bairro, tipo_endereco, latitude, longitude)
    SELECT p.pessoa_id, '89460-000', 'Rua das Flores', c.id, 100, 'Centro', 'residencial', -26.1766, -50.3897
    FROM cidade c, pessoa p
    WHERE c.nome = 'Canoinhas'
      AND p.cpf_cnpj = '11111111111'
    ON CONFLICT DO NOTHING;

    -- Endereço do restaurante
    INSERT INTO endereco (id_pessoa, cep, logradouro, cidade_id, numero, bairro, tipo_endereco, latitude, longitude)
    SELECT p.pessoa_id, '89460-100', 'Avenida Brasil', c.id, 500, 'Centro', 'comercial', -26.1780, -50.3910
    FROM cidade c, pessoa p
    WHERE c.nome = 'Canoinhas'
      AND p.cpf_cnpj = '22222222000122'
    ON CONFLICT DO NOTHING;

    INSERT INTO restaurante (pessoa_id, nome, status_funcionamento, tipo_cozinha_id)
    SELECT p.pessoa_id, 'Pizzaria do João', TRUE, tc.id
    FROM tipo_cozinha tc, pessoa p
    WHERE tc.tipo = 'Pizzaria'
      AND p.cpf_cnpj = '22222222000122'
    ON CONFLICT DO NOTHING;

    INSERT INTO entregador (pessoa_id, disponivel, latitude, longitude)
    SELECT p.pessoa_id, TRUE, -26.1750, -50.3880
    FROM pessoa p
    WHERE p.cpf_cnpj = '33333333333'
    ON CONFLICT DO NOTHING;

    -- Produtos (com custo — dado protegido pela view cardapio_online)
    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    SELECT 'Pizza Margherita', 'Pizza', 45.00, 18.00, r.id
    FROM restaurante r WHERE r.nome = 'Pizzaria do João'
    ON CONFLICT DO NOTHING;

    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    SELECT 'Refrigerante Lata', 'Bebida', 7.00, 2.50, r.id
    FROM restaurante r WHERE r.nome = 'Pizzaria do João'
    ON CONFLICT DO NOTHING;

    RAISE NOTICE 'Dados de teste inseridos com sucesso.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERRO: %', SQLERRM;
        RAISE;
END;
$$;


-- ── Bloco 2: criar pedido com SAVEPOINT ──────────────────────────
--
--  RETURNING id INTO variavel → captura o ID gerado pelo SERIAL
--  sem precisar fazer um SELECT separado depois.

DO $$
DECLARE
    v_nome_restaurante  TEXT := 'Pizzaria do João';
    v_nome_cliente      TEXT := 'Ana Souza';
    v_pedido_id      INTEGER;
    v_produto_id     INTEGER;
    v_restaurante_id INTEGER;
    v_cliente_id     INTEGER;
BEGIN
    SELECT r.id INTO v_restaurante_id
    FROM restaurante r
    WHERE r.nome = v_nome_restaurante;
    SELECT id INTO v_produto_id     FROM produto WHERE nome = 'Pizza Margherita' LIMIT 1;
    SELECT pessoa_id INTO v_cliente_id
    FROM pessoa
    WHERE nome = v_nome_cliente;

    SAVEPOINT sp_antes_pedido;  -- ponto de restauração antes do pedido

    INSERT INTO pedido (cliente_id, restaurante_id, status, data_hora, taxa_entrega, valor_total)
    VALUES (
        v_cliente_id, v_restaurante_id,
        (SELECT id FROM status_de_pedido WHERE status = 'Pendente'),
        NOW(), 5.00, 50.00
    )
    RETURNING id INTO v_pedido_id;  -- captura o ID gerado automaticamente

    RAISE NOTICE 'Pedido % criado. Inserindo itens...', v_pedido_id;

    SAVEPOINT sp_antes_itens;  -- ponto de restauração antes dos itens

    INSERT INTO pedido_itens (pedido_id, produto_id, quantidade)
    VALUES (v_pedido_id, v_produto_id, 1);

    INSERT INTO pagamento (pedido_id, metodo_id, status_id)
    VALUES (
        v_pedido_id,
        (SELECT id FROM metodo_pagamento WHERE metodo = 'Pix'),
        (SELECT id FROM status_pagamento  WHERE status = 'Pendente')
    );

    RAISE NOTICE 'Pedido % completo com itens e pagamento.', v_pedido_id;
EXCEPTION
    WHEN OTHERS THEN
        -- Falhou nos itens: desfaz só essa parte, não o pedido inteiro
        ROLLBACK TO SAVEPOINT sp_antes_itens;
        RAISE NOTICE 'ERRO nos itens do pedido %: %', v_pedido_id, SQLERRM;
        RAISE;
END;
$$;


-- ── Bloco 3: atualizar status (dispara a trigger automaticamente) ─
--
--  A CADA UPDATE no campo status, a trigger trg_historico_pedido
--  grava um registro em historico_pedido sem nenhuma ação manual.

DO $$
DECLARE
    v_nome_cliente TEXT := 'Ana Souza';
    v_pedido_id INTEGER;
BEGIN
    SELECT id INTO v_pedido_id
    FROM pedido
    WHERE cliente_id = (SELECT pessoa_id FROM pessoa WHERE nome = v_nome_cliente)
    ORDER BY id DESC LIMIT 1;

    IF v_pedido_id IS NULL THEN
        RAISE NOTICE 'Nenhum pedido encontrado.';
        RETURN;
    END IF;

    -- Cada UPDATE abaixo dispara a trigger → historico_pedido é preenchido sozinho
    UPDATE pedido SET status = (SELECT id FROM status_de_pedido WHERE status = 'Aceito')
    WHERE id = v_pedido_id;
    RAISE NOTICE 'Status → Aceito (trigger disparada)';

    UPDATE pedido SET status = (SELECT id FROM status_de_pedido WHERE status = 'Em preparo')
    WHERE id = v_pedido_id;
    RAISE NOTICE 'Status → Em preparo (trigger disparada)';

    UPDATE pedido SET status = (SELECT id FROM status_de_pedido WHERE status = 'Saiu para entrega')
    WHERE id = v_pedido_id;
    RAISE NOTICE 'Status → Saiu para entrega (trigger disparada)';

    UPDATE pagamento
    SET status_id = (SELECT id FROM status_pagamento WHERE status = 'Pago')
    WHERE pedido_id = v_pedido_id;
    RAISE NOTICE 'Pagamento confirmado.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERRO: %', SQLERRM;
        RAISE;
END;
$$;


-- ── Bloco 4: teste da trigger de restaurante fechado ─────────────
--
--  Demonstra que a trigger BEFORE INSERT bloqueia o pedido.
--  O bloco EXCEPTION captura o erro lançado pela trigger.

DO $$
DECLARE
    v_nome_restaurante TEXT := 'Pizzaria do João LTDA';
    v_nome_cliente     TEXT := 'Ana Souza';
BEGIN
    UPDATE restaurante
    SET status_funcionamento = FALSE
    WHERE id = (
        SELECT r.id
        FROM restaurante r
        JOIN pessoa p ON p.pessoa_id = r.pessoa_id
        WHERE p.nome = v_nome_restaurante
    );
    RAISE NOTICE 'Restaurante fechado. Tentando criar pedido (deve falhar)...';

    INSERT INTO pedido (cliente_id, restaurante_id, status, data_hora, taxa_entrega, valor_total)
        SELECT p.pessoa_id, r.id,
           (SELECT id FROM status_de_pedido WHERE status = 'Pendente'),
           NOW(), 5.00, 50.00
        FROM restaurante r
        CROSS JOIN pessoa p
        WHERE p.nome = v_nome_cliente
          AND r.id = (
              SELECT rr.id
              FROM restaurante rr
              JOIN pessoa rp ON rp.pessoa_id = rr.pessoa_id
              WHERE rp.nome = v_nome_restaurante
          );

    RAISE NOTICE 'PROBLEMA: pedido criado mesmo com restaurante fechado!';
EXCEPTION
    WHEN OTHERS THEN
        -- Comportamento esperado: a trigger lançou exceção
        RAISE NOTICE 'CORRETO! Trigger bloqueou: %', SQLERRM;
        UPDATE restaurante
        SET status_funcionamento = TRUE
        WHERE id = (
            SELECT r.id
            FROM restaurante r
            JOIN pessoa p ON p.pessoa_id = r.pessoa_id
            WHERE p.nome = v_nome_restaurante
        );
        RAISE NOTICE 'Restaurante reaberto.';
END;
$$;


-- ── Bloco 5: DELETE com SAVEPOINT e ROLLBACK parcial ─────────────
--
--  Demonstra que ROLLBACK TO SAVEPOINT restaura apenas
--  as operações feitas APÓS aquele ponto, não tudo.

DO $$
DECLARE
    v_total_antes  INTEGER;
    v_total_depois INTEGER;
BEGIN
    SELECT COUNT(*) INTO v_total_antes FROM produto;
    RAISE NOTICE 'Produtos antes do DELETE: %', v_total_antes;

    SAVEPOINT sp_antes_delete;  -- marca o ponto antes do delete perigoso

    DELETE FROM produto;  -- simula um erro humano

    SELECT COUNT(*) INTO v_total_depois FROM produto;
    RAISE NOTICE 'Após DELETE: % produtos', v_total_depois;

    -- Percebemos o erro e voltamos ao savepoint
    ROLLBACK TO SAVEPOINT sp_antes_delete;

    SELECT COUNT(*) INTO v_total_depois FROM produto;
    RAISE NOTICE 'Após ROLLBACK TO SAVEPOINT: % produtos restaurados.', v_total_depois;
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERRO: %', SQLERRM;
        RAISE;
END;
$$;


-- ── Bloco 6: usar a procedure calcular_taxa_entrega ───────────────

DO $$
DECLARE
    v_taxa FLOAT;
BEGIN
    -- Chama a procedure — o parâmetro OUT (v_taxa) é preenchido por ela
    CALL calcular_taxa_entrega(8.0, v_taxa);
    RAISE NOTICE 'Taxa para 8km: R$ %', v_taxa;

    UPDATE pedido
    SET taxa_entrega = v_taxa
    WHERE id = (SELECT id FROM pedido ORDER BY id DESC LIMIT 1);

    RAISE NOTICE 'Taxa atualizada no pedido.';
EXCEPTION
    WHEN OTHERS THEN
        RAISE NOTICE 'ERRO: %', SQLERRM;
        RAISE;
END;
$$;


-- ── Verificação: histórico gerado automaticamente pelas triggers ──

SELECT
    hp.id,
    hp.pedido_id,
    s_ant.status    AS status_anterior,
    s_nov.status    AS status_novo,
    hp.data_alteracao
FROM historico_pedido hp
JOIN status_de_pedido s_ant ON s_ant.id = hp.status_anterior_id
JOIN status_de_pedido s_nov ON s_nov.id = hp.status_novo_id
ORDER BY hp.id;




-- ================================================================
-- ▌ PARTE 4 — SQL AVANÇADO
-- ================================================================
--
--  Três técnicas que tornam consultas complexas legíveis
--  e eficientes: subqueries correlacionadas, CTEs e
--  window functions.
-- ================================================================


-- ── Subqueries correlacionadas ────────────────────────────────────
--
--  CONCEITO:
--    Uma subquery que referencia a consulta externa.
--    Executa uma vez para CADA LINHA da consulta de fora.
--    Diferente de uma subquery normal, que executa apenas uma vez.
--
--  EXISTS → retorna TRUE se a subquery retornar pelo menos uma linha.
--  Mais eficiente que IN quando há muitas linhas, pois para
--  na primeira correspondência encontrada.


-- Restaurantes abertos que têm ao menos um produto cadastrado
SELECT
    r.id,
    r.nome                  AS restaurante,
    r.status_funcionamento  AS aberto
FROM restaurante r
WHERE r.status_funcionamento = TRUE
  AND EXISTS (
      -- Para cada restaurante, verifica se existe produto vinculado
      SELECT 1 FROM produto p WHERE p.restaurante_id = r.id
  );


-- Clientes que já fizeram pelo menos um pedido
SELECT
    p.nome      AS cliente,
    p.cpf_cnpj
FROM pessoa p
WHERE p.tipo_pessoa_id = (SELECT id FROM tipo_pessoa WHERE tipo = 'Cliente')
  AND EXISTS (
      SELECT 1 FROM pedido ped WHERE ped.cliente_id = p.pessoa_id
  );


-- Produtos com preço acima da média DO SEU PRÓPRIO restaurante
-- (a subquery calcula a média só dos produtos do mesmo restaurante)
SELECT
    p.nome          AS produto,
    p.preco,
    r.nome          AS restaurante
FROM produto p
JOIN restaurante r ON r.id = p.restaurante_id
WHERE p.preco > (
    SELECT AVG(p2.preco)
    FROM produto p2
    WHERE p2.restaurante_id = p.restaurante_id  -- ← correlação com a consulta externa
);


-- ── CTEs (Common Table Expressions) ──────────────────────────────
--
--  CONCEITO:
--    Bloco nomeado definido com WITH antes do SELECT principal.
--    Funciona como uma "view temporária" que existe só naquela query.
--    Deixa o código muito mais legível que subqueries aninhadas.
--
--  Estrutura:
--    WITH nome AS (SELECT ...)
--    SELECT * FROM nome;


-- Total de pedidos e valor gasto por cliente
WITH resumo_clientes AS (
    -- Etapa 1: agrupa pedidos por cliente
    SELECT
        ped.cliente_id,
        COUNT(ped.id)        AS total_pedidos,
        SUM(ped.valor_total) AS valor_total_gasto
    FROM pedido ped
    GROUP BY ped.cliente_id
)
-- Etapa 2: junta com pessoa para trazer o nome
SELECT
    p.nome              AS cliente,
    rc.total_pedidos,
    rc.valor_total_gasto
FROM resumo_clientes rc
JOIN pessoa p ON p.pessoa_id = rc.cliente_id
ORDER BY rc.valor_total_gasto DESC;


-- Desempenho dos entregadores
WITH desempenho AS (
    SELECT
        ped.entregador_id,
        COUNT(ped.id)           AS total_entregas,
        AVG(ped.taxa_entrega)   AS media_taxa,
        SUM(ped.valor_total)    AS valor_total_entregue
    FROM pedido ped
    WHERE ped.entregador_id IS NOT NULL
    GROUP BY ped.entregador_id
)
SELECT
    p.nome                                      AS entregador,
    d.total_entregas,
    ROUND(d.media_taxa::NUMERIC, 2)             AS media_taxa_entrega,
    ROUND(d.valor_total_entregue::NUMERIC, 2)   AS valor_total_entregue
FROM desempenho d
JOIN entregador e ON e.id = d.entregador_id
JOIN pessoa p     ON p.pessoa_id = e.pessoa_id
ORDER BY d.total_entregas DESC;


-- CTEs encadeadas: uma CTE usando outra
WITH pedidos_por_restaurante AS (
    -- CTE 1: faturamento por restaurante
    SELECT
        ped.restaurante_id,
        COUNT(ped.id)        AS total_pedidos,
        SUM(ped.valor_total) AS faturamento
    FROM pedido ped
    GROUP BY ped.restaurante_id
),
restaurantes_ativos AS (
    -- CTE 2: filtra só os que têm pedidos (usa a CTE 1)
    SELECT * FROM pedidos_por_restaurante WHERE total_pedidos > 0
)
SELECT
    r.nome                                  AS restaurante,
    ra.total_pedidos,
    ROUND(ra.faturamento::NUMERIC, 2)       AS faturamento_total
FROM restaurantes_ativos ra
JOIN restaurante r ON r.id = ra.restaurante_id
ORDER BY ra.faturamento DESC;


-- ── Window Functions ──────────────────────────────────────────────
--
--  CONCEITO:
--    Calcula um valor para cada linha comparando com outras
--    linhas do mesmo grupo, SEM colapsar como GROUP BY faz.
--
--    GROUP BY  → várias linhas viram uma por grupo
--    WINDOW    → cada linha mantém seus dados + valor calculado
--
--  Funções principais:
--    RANK()       → posição (empates repetem, próximo número pula)
--    ROW_NUMBER() → numeração única (nunca empata)
--    SUM() OVER   → soma acumulada linha a linha
--
--  Estrutura:
--    FUNÇÃO() OVER (
--        PARTITION BY coluna  ← divide em grupos (reinicia o cálculo)
--        ORDER BY coluna      ← ordena dentro do grupo
--    )


-- Ranking de entregadores por total de entregas
SELECT
    p.nome                  AS entregador,
    COUNT(ped.id)           AS total_entregas,
    RANK() OVER (
        ORDER BY COUNT(ped.id) DESC  -- quem entregou mais fica em 1º
    )                       AS posicao_ranking
FROM pedido ped
JOIN entregador e ON e.id = ped.entregador_id
JOIN pessoa p     ON p.pessoa_id = e.pessoa_id
WHERE ped.entregador_id IS NOT NULL
GROUP BY p.nome;


-- Soma acumulada de faturamento por data
-- Mostra quanto foi faturado no total até cada pedido
SELECT
    ped.id          AS pedido_id,
    ped.data_hora,
    ped.valor_total,
    SUM(ped.valor_total) OVER (
        ORDER BY ped.data_hora
        ROWS BETWEEN UNBOUNDED PRECEDING AND CURRENT ROW
        -- ↑ soma de todas as linhas anteriores até a atual
    )               AS faturamento_acumulado
FROM pedido ped
ORDER BY ped.data_hora;


-- Ranking de preço DENTRO de cada restaurante (PARTITION BY)
-- PARTITION BY faz o ranking reiniciar a cada restaurante diferente
SELECT
    r.nome          AS restaurante,
    p.nome          AS produto,
    p.preco,
    RANK() OVER (
        PARTITION BY p.restaurante_id  -- ← reinicia o rank por restaurante
        ORDER BY p.preco DESC          -- produto mais caro = posição 1
    )               AS posicao_no_restaurante
FROM produto p
JOIN restaurante r ON r.id = p.restaurante_id
ORDER BY r.nome, posicao_no_restaurante;


-- CTE + Window Function combinados
WITH totais_clientes AS (
    SELECT
        ped.cliente_id,
        COUNT(ped.id)        AS total_pedidos,
        SUM(ped.valor_total) AS valor_gasto
    FROM pedido ped
    GROUP BY ped.cliente_id
)
SELECT
    p.nome                                  AS cliente,
    tc.total_pedidos,
    ROUND(tc.valor_gasto::NUMERIC, 2)       AS valor_gasto,
    -- ROW_NUMBER: nunca empata, cada linha tem número único
    ROW_NUMBER() OVER (ORDER BY tc.valor_gasto DESC)    AS posicao_por_valor,
    -- RANK: empata quando valores são iguais
    RANK()       OVER (ORDER BY tc.total_pedidos DESC)  AS posicao_por_pedidos
FROM totais_clientes tc
JOIN pessoa p ON p.pessoa_id = tc.cliente_id
ORDER BY posicao_por_valor;




-- ================================================================
-- ▌ PARTE 5 — SEGURANÇA
-- ================================================================
--
--  CONCEITO:
--    1. ROLE   → perfil de acesso (como um "crachá")
--    2. GRANT  → dá permissão a um role
--    3. REVOKE → remove permissão
--    4. RLS    → Row Level Security: controla quais LINHAS
--                cada usuário enxerga dentro de uma tabela
--
--  Três perfis no sistema:
--    role_cliente     → vê cardápio e seus próprios pedidos
--    role_restaurante → gerencia produtos e pedidos do seu restaurante
--    role_entregador  → vê e atualiza pedidos atribuídos a ele
-- ================================================================


-- ── Criar os perfis de acesso ─────────────────────────────────────

DROP ROLE IF EXISTS role_cliente;
DROP ROLE IF EXISTS role_restaurante;
DROP ROLE IF EXISTS role_entregador;

-- NOLOGIN = é um perfil, não faz login diretamente
CREATE ROLE role_cliente     NOLOGIN;
CREATE ROLE role_restaurante NOLOGIN;
CREATE ROLE role_entregador  NOLOGIN;


-- ── Permissões do cliente ─────────────────────────────────────────
--
--  ✓ Ver cardápio (via view — sem expor custo)
--  ✓ Criar e ver seus pedidos
--  ✗ Não acessa produto diretamente (tem coluna custo)
--  ✗ Não vê pedidos de outros clientes (RLS cuida disso)

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


-- ── Permissões do restaurante ─────────────────────────────────────
--
--  ✓ Gerenciar seus produtos (INSERT, UPDATE, DELETE)
--  ✓ Ver e atualizar pedidos
--  ✗ Não vê dados pessoais de clientes

GRANT SELECT, INSERT, UPDATE, DELETE ON produto TO role_restaurante;
GRANT USAGE, SELECT ON SEQUENCE produto_id_seq TO role_restaurante;
GRANT SELECT, UPDATE ON pedido          TO role_restaurante;
GRANT SELECT         ON pedido_itens    TO role_restaurante;
GRANT SELECT         ON historico_pedido TO role_restaurante;
GRANT SELECT         ON status_de_pedido TO role_restaurante;


-- ── Permissões do entregador ──────────────────────────────────────
--
--  GRANT UPDATE (status) → permissão apenas na COLUNA status,
--  não no registro inteiro. Boa prática: mínimo privilégio necessário.

GRANT SELECT ON pedido          TO role_entregador;
GRANT UPDATE (status)           ON pedido     TO role_entregador;  -- só a coluna status
GRANT UPDATE (disponivel, latitude, longitude) ON entregador TO role_entregador;
GRANT SELECT ON entregador      TO role_entregador;
GRANT SELECT ON status_de_pedido TO role_entregador;


-- ── REVOKE: garantir que dados sensíveis não fiquem expostos ──────
--
--  O PostgreSQL por padrão pode herdar permissões do role "public".
--  REVOKE ALL FROM PUBLIC garante que ninguém acessa sem permissão explícita.

REVOKE ALL ON produto       FROM PUBLIC;  -- clientes só via cardapio_online
REVOKE ALL ON pessoa        FROM PUBLIC;  -- dados pessoais protegidos
REVOKE ALL ON colaboradores FROM PUBLIC;  -- salários protegidos
REVOKE ALL ON pagamento     FROM PUBLIC;
GRANT SELECT, INSERT, UPDATE, DELETE ON produto   TO role_restaurante;
GRANT INSERT, SELECT                 ON pagamento TO role_cliente;
GRANT SELECT                         ON pagamento TO role_restaurante;


-- ── Criar usuários e atribuir perfis ─────────────────────────────

DROP USER IF EXISTS usuario_cliente;
DROP USER IF EXISTS usuario_restaurante;
DROP USER IF EXISTS usuario_entregador;

CREATE USER usuario_cliente     WITH LOGIN PASSWORD 'senha_cliente123';
CREATE USER usuario_restaurante WITH LOGIN PASSWORD 'senha_rest456';
CREATE USER usuario_entregador  WITH LOGIN PASSWORD 'senha_ent789';

-- Usuário herda todas as permissões do seu role
GRANT role_cliente     TO usuario_cliente;
GRANT role_restaurante TO usuario_restaurante;
GRANT role_entregador  TO usuario_entregador;


-- ── Row Level Security (RLS) ──────────────────────────────────────
--
--  CONCEITO:
--    GRANT/REVOKE controla QUAIS TABELAS o usuário acessa.
--    RLS controla QUAIS LINHAS ele enxerga dentro da tabela.
--
--    Exemplo: cliente pode fazer SELECT em pedido,
--    mas a política garante que só vê os seus próprios pedidos.

ALTER TABLE pedido ENABLE ROW LEVEL SECURITY;

-- Cliente só enxerga pedidos onde cliente_id = seu login
CREATE POLICY politica_cliente_pedido
    ON pedido FOR SELECT TO role_cliente
    USING (cliente_id = current_user);
--          ↑ current_user retorna o nome do usuário logado

-- Entregador só enxerga pedidos atribuídos a ele
CREATE POLICY politica_entregador_pedido
    ON pedido FOR SELECT TO role_entregador
    USING (
        entregador_id = (
            SELECT id FROM entregador WHERE pessoa_id = current_user
        )
    );


-- ── Verificação de roles e permissões ────────────────────────────

SELECT rolname, rolcanlogin, rolcreatedb
FROM pg_roles
WHERE rolname IN ('role_cliente', 'role_restaurante', 'role_entregador',
                  'usuario_cliente', 'usuario_restaurante', 'usuario_entregador');

SELECT grantee, privilege_type, is_grantable
FROM information_schema.role_table_grants
WHERE table_name = 'pedido'
ORDER BY grantee, privilege_type;


-- ── Referência: Backup e Restore (rodar no terminal) ─────────────
--
--  Backup completo (formato compactado, mais eficiente):
--    pg_dump -h localhost -U postgres -Fc -b -v -f delivery_backup.dump delivery
--
--  Backup só do schema (estrutura sem dados):
--    pg_dump -h localhost -U postgres --schema-only -f delivery_schema.sql delivery
--
--  Backup de uma tabela específica (ex: antes de campanha de preços):
--    pg_dump -h localhost -U postgres -t produto -Fc -f backup_produtos.dump delivery
--
--  Restore:
--    pg_restore -h localhost -U postgres -d delivery -v delivery_backup.dump




-- ================================================================
-- ▌ PARTE 6 — ÍNDICES E OTIMIZAÇÃO
-- ================================================================
--
--  CONCEITO:
--    Sem índice → Seq Scan: banco lê TODAS as linhas da tabela.
--    Com índice → Index Scan: banco vai direto nas linhas
--                 relevantes usando uma estrutura B-Tree.
--
--  Quando criar índice:
--    ✓ Colunas usadas frequentemente em WHERE
--    ✓ Chaves estrangeiras usadas em JOIN
--    ✓ Colunas em ORDER BY de consultas lentas
--
--  Quando NÃO criar:
--    ✗ Tabelas muito pequenas (seq scan pode ser mais rápido)
--    ✗ Colunas booleanas com poucos valores distintos
--    ✗ Colunas que mudam muito (INSERT/UPDATE ficam mais lentos)
-- ================================================================


-- ── Criação dos índices ───────────────────────────────────────────

-- Filtro de cardápio por tipo de produto ("mostre só pizzas no menu")
CREATE INDEX IF NOT EXISTS idx_produto_tipo
    ON produto (tipo);

-- Filtro de restaurantes por tipo de cozinha (pedido original do professor:
-- "índice em tipo de cozinha" — ex: "mostre só pizzarias")
CREATE INDEX IF NOT EXISTS idx_restaurante_tipo_cozinha
    ON restaurante (tipo_cozinha_id);

-- Busca por CEP (localização de entrega)
CREATE INDEX IF NOT EXISTS idx_endereco_cep
    ON endereco (cep);

-- Coordenadas usadas pela procedure atribuir_entregador
CREATE INDEX IF NOT EXISTS idx_endereco_coordenadas
    ON endereco (latitude, longitude);

-- Consulta mais comum: "pedidos pendentes" / "prontos para entrega"
CREATE INDEX IF NOT EXISTS idx_pedido_status
    ON pedido (status);

-- Cliente abre o app e vê seu histórico
CREATE INDEX IF NOT EXISTS idx_pedido_cliente
    ON pedido (cliente_id);

-- Restaurante consulta seus pedidos
CREATE INDEX IF NOT EXISTS idx_pedido_restaurante
    ON pedido (restaurante_id);

-- Consulta crítica a cada acesso ao app: "restaurantes abertos agora"
CREATE INDEX IF NOT EXISTS idx_restaurante_status
    ON restaurante (status_funcionamento);

-- Procedure atribuir_entregador filtra por disponivel = TRUE
CREATE INDEX IF NOT EXISTS idx_entregador_disponivel
    ON entregador (disponivel);

-- Índice ÚNICO na view materializada (obrigatório para REFRESH CONCURRENTLY)
CREATE UNIQUE INDEX IF NOT EXISTS idx_desempenho_entregador_id
    ON desempenho_entregadores (entregador_id);

-- Atualiza a view sem bloquear leituras simultâneas
REFRESH MATERIALIZED VIEW CONCURRENTLY desempenho_entregadores;


-- ── EXPLAIN ANALYZE: comparação antes e depois do índice ─────────
--
--  EXPLAIN       → mostra o plano sem executar
--  EXPLAIN ANALYZE → executa e mostra tempo real
--
--  O que observar:
--    Seq Scan   → leu a tabela toda (ruim em tabelas grandes)
--    Index Scan → usou o índice (bom!)
--    cost=X..Y  → custo estimado (X=início, Y=total)
--    actual time=X..Y → tempo real em milissegundos


-- Restaurantes abertos (consulta crítica — executada a cada acesso)
EXPLAIN ANALYZE
SELECT r.id, r.nome, p.nome AS dono
FROM restaurante r
JOIN pessoa p ON p.pessoa_id = r.pessoa_id
WHERE r.status_funcionamento = TRUE;
-- Esperado: Index Scan using idx_restaurante_status


-- Pedidos de um cliente específico
EXPLAIN ANALYZE
SELECT ped.id, ped.data_hora, ped.valor_total, s.status
FROM pedido ped
JOIN status_de_pedido s ON s.id = ped.status
WHERE ped.cliente_id = (SELECT pessoa_id FROM pessoa WHERE cpf_cnpj = '11111111111')
ORDER BY ped.data_hora DESC;
-- Esperado: Index Scan using idx_pedido_cliente


-- Produtos por tipo (filtro de cardápio)
EXPLAIN ANALYZE
SELECT p.nome, p.preco, r.nome AS restaurante
FROM produto p
JOIN restaurante r ON r.id = p.restaurante_id
WHERE p.tipo = 'Pizza' AND r.status_funcionamento = TRUE;
-- Esperado: Index Scan using idx_produto_tipo


-- ── Comparação forçada: Seq Scan vs Index Scan ────────────────────
--
--  Desativa os índices temporariamente para mostrar
--  a diferença no plano de execução.

-- Passo 1: força Seq Scan (sem índice)
SET enable_indexscan  = OFF;
SET enable_bitmapscan = OFF;

EXPLAIN ANALYZE
SELECT * FROM pedido WHERE cliente_id = (SELECT pessoa_id FROM pessoa WHERE cpf_cnpj = '11111111111');
-- Plano mostra: Seq Scan on pedido (lê TODAS as linhas)

-- Passo 2: reativa e mostra com índice
SET enable_indexscan  = ON;
SET enable_bitmapscan = ON;

EXPLAIN ANALYZE
SELECT * FROM pedido WHERE cliente_id = (SELECT pessoa_id FROM pessoa WHERE cpf_cnpj = '11111111111');
-- Plano mostra: Index Scan using idx_pedido_cliente (lê só as linhas do cliente)


-- ── Listagem de todos os índices criados ─────────────────────────

SELECT
    indexname   AS nome_indice,
    tablename   AS tabela,
    indexdef    AS definicao
FROM pg_indexes
WHERE schemaname = 'public'
  AND indexname LIKE 'idx_%'
ORDER BY tablename, indexname;
