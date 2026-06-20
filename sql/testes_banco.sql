-- ============================================================
-- Sistema de Delivery - Banco de Dados II
-- Script de teste: popula o banco e mostra o fluxo todo rodando
-- ============================================================

-- ================================================================
-- MOMENTO 1 - CADASTRO DO DONO E DO CLIENTE
-- ================================================================

DO $$
DECLARE
    v_tipo_pf_id          INTEGER;
    v_tipo_pj_id          INTEGER;
    v_tipo_cliente_id     INTEGER;
    v_tipo_restaurante_id INTEGER;
BEGIN
    SELECT id INTO v_tipo_pf_id FROM tipo_cadastro WHERE tipo = 'PF';
    SELECT id INTO v_tipo_pj_id FROM tipo_cadastro WHERE tipo = 'PJ';
    SELECT id INTO v_tipo_cliente_id FROM tipo_pessoa WHERE tipo = 'Cliente';
    SELECT id INTO v_tipo_restaurante_id FROM tipo_pessoa WHERE tipo = 'Restaurante';

    INSERT INTO pessoa (cpf_cnpj, nome, login_usuario, tipo_cadastro, tipo_pessoa_id)
    VALUES ('22222222000122', 'Pizzaria do Joao LTDA', 'usuario_restaurante', v_tipo_pj_id, v_tipo_restaurante_id)
    ON CONFLICT (cpf_cnpj) DO NOTHING;

    INSERT INTO pessoa (cpf_cnpj, nome, login_usuario, tipo_cadastro, tipo_pessoa_id)
    VALUES ('11111111111', 'Ana Souza', 'usuario_cliente', v_tipo_pf_id, v_tipo_cliente_id)
    ON CONFLICT (cpf_cnpj) DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 2 - CADASTRO DO ENTREGADOR
-- ================================================================

DO $$
DECLARE
    v_tipo_pf_id          INTEGER;
    v_tipo_entregador_id  INTEGER;
BEGIN
    SELECT id INTO v_tipo_pf_id FROM tipo_cadastro WHERE tipo = 'PF';
    SELECT id INTO v_tipo_entregador_id FROM tipo_pessoa WHERE tipo = 'Entregador';

    INSERT INTO pessoa (cpf_cnpj, nome, login_usuario, tipo_cadastro, tipo_pessoa_id)
    VALUES ('33333333333', 'Carlos Moto', 'usuario_entregador', v_tipo_pf_id, v_tipo_entregador_id)
    ON CONFLICT (cpf_cnpj) DO NOTHING;

    INSERT INTO pessoa (cpf_cnpj, nome, login_usuario, tipo_cadastro, tipo_pessoa_id)
    VALUES ('44444444444', 'Marina Entrega', NULL, v_tipo_pf_id, v_tipo_entregador_id)
    ON CONFLICT (cpf_cnpj) DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 3 - ENDERECO DO DONO DO RESTAURANTE
-- ================================================================

DO $$
DECLARE
    v_estado_id    INTEGER;
    v_cidade_id    INTEGER;
    v_dono_id      INTEGER;
BEGIN
    INSERT INTO estado (nome)
    VALUES ('Santa Catarina')
    ON CONFLICT DO NOTHING;

    SELECT id INTO v_estado_id
    FROM estado
    WHERE nome = 'Santa Catarina';

    INSERT INTO cidade (nome, estado_id)
    VALUES ('Canoinhas', v_estado_id)
    ON CONFLICT DO NOTHING;

    SELECT id INTO v_cidade_id
    FROM cidade
    WHERE nome = 'Canoinhas'
      AND estado_id = v_estado_id;

    SELECT pessoa_id INTO v_dono_id
    FROM pessoa
    WHERE cpf_cnpj = '22222222000122';

    INSERT INTO endereco (
        id_pessoa, cep, tipo_logradouro_id, logradouro, cidade_id,
        numero, bairro, tipo_endereco, latitude, longitude
    )
    VALUES (
        v_dono_id, '89460-100', (SELECT id FROM tipo_logradouro WHERE tipo = 'Avenida' LIMIT 1),
        'Avenida Brasil', v_cidade_id, 500, 'Centro', 'comercial', -26.1780, -50.3910
    )
    ON CONFLICT DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 4 - ENDERECO DO CLIENTE
-- ================================================================

DO $$
DECLARE
    v_estado_id    INTEGER;
    v_cidade_id    INTEGER;
    v_cliente_id   INTEGER;
BEGIN
    SELECT id INTO v_estado_id
    FROM estado
    WHERE nome = 'Santa Catarina';

    SELECT id INTO v_cidade_id
    FROM cidade
    WHERE nome = 'Canoinhas'
      AND estado_id = v_estado_id;

    SELECT pessoa_id INTO v_cliente_id
    FROM pessoa
    WHERE cpf_cnpj = '11111111111';

    INSERT INTO endereco (
        id_pessoa, cep, tipo_logradouro_id, logradouro, cidade_id,
        numero, bairro, tipo_endereco, latitude, longitude
    )
    VALUES (
        v_cliente_id, '89460-000', (SELECT id FROM tipo_logradouro WHERE tipo = 'Rua' LIMIT 1),
        'Rua das Flores', v_cidade_id, 100, 'Centro', 'residencial', -26.1766, -50.3897
    )
    ON CONFLICT DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 5 - CADASTRO DO RESTAURANTE
-- ================================================================

DO $$
DECLARE
    v_dono_id         INTEGER;
    v_tipo_cozinha_id INTEGER;
BEGIN
    SELECT pessoa_id INTO v_dono_id
    FROM pessoa
    WHERE cpf_cnpj = '22222222000122';

    SELECT id INTO v_tipo_cozinha_id
    FROM tipo_cozinha
    WHERE tipo = 'Pizzaria';

    INSERT INTO restaurante (pessoa_id, nome, status_funcionamento, tipo_cozinha_id)
    VALUES (v_dono_id, 'Pizzaria do Joao', TRUE, v_tipo_cozinha_id)
    ON CONFLICT DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 6 - CADASTRO DOS PRODUTOS
-- ================================================================

DO $$
DECLARE
    v_restaurante_id INTEGER;
BEGIN
    SELECT id INTO v_restaurante_id
    FROM restaurante
    WHERE nome = 'Pizzaria do Joao';

    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    VALUES ('Pizza Margherita', 'Pizza', 45.00, 18.00, v_restaurante_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    VALUES ('Refrigerante Lata', 'Bebida', 7.00, 2.50, v_restaurante_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    VALUES ('Pizza Calabresa', 'Pizza', 49.00, 19.50, v_restaurante_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    VALUES ('Pizza Quatro Queijos', 'Pizza', 52.00, 21.00, v_restaurante_id)
    ON CONFLICT DO NOTHING;

    INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
    VALUES ('Suco Natural', 'Bebida', 9.00, 3.00, v_restaurante_id)
    ON CONFLICT DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 7 - CADASTRO DOS ENTREGADORES
-- ================================================================

DO $$
DECLARE
    v_entregador_1_id INTEGER;
    v_entregador_2_id INTEGER;
BEGIN
    SELECT pessoa_id INTO v_entregador_1_id
    FROM pessoa
    WHERE cpf_cnpj = '33333333333';

    SELECT pessoa_id INTO v_entregador_2_id
    FROM pessoa
    WHERE cpf_cnpj = '44444444444';

    INSERT INTO entregador (pessoa_id, disponivel, latitude, longitude)
    VALUES (v_entregador_1_id, TRUE, -26.1750, -50.3880)
    ON CONFLICT DO NOTHING;

    INSERT INTO entregador (pessoa_id, disponivel, latitude, longitude)
    VALUES (v_entregador_2_id, TRUE, -26.1800, -50.3950)
    ON CONFLICT DO NOTHING;
END;
$$;


-- ================================================================
-- MOMENTO 8 - CRIACAO DO PEDIDO
-- ================================================================

DO $$
DECLARE
    v_cliente_id     INTEGER;
    v_restaurante_id INTEGER;
    v_pedido_id      INTEGER;
    v_produto_id     INTEGER;
    v_cliente_lat    NUMERIC;
    v_cliente_lon    NUMERIC;
    v_rest_lat       NUMERIC;
    v_rest_lon       NUMERIC;
    v_distancia      FLOAT;
    v_taxa           FLOAT;
BEGIN
    SELECT pessoa_id INTO v_cliente_id
    FROM pessoa
    WHERE cpf_cnpj = '11111111111';

    SELECT id INTO v_restaurante_id
    FROM restaurante
    WHERE nome = 'Pizzaria do Joao';

    SELECT id INTO v_produto_id
    FROM produto
    WHERE nome = 'Pizza Margherita'
      AND restaurante_id = v_restaurante_id
    LIMIT 1;

    SELECT latitude, longitude INTO v_cliente_lat, v_cliente_lon
    FROM endereco
    WHERE id_pessoa = v_cliente_id
      AND tipo_endereco = 'residencial'
    LIMIT 1;

    SELECT latitude, longitude INTO v_rest_lat, v_rest_lon
    FROM endereco
    WHERE id_pessoa = (
        SELECT pessoa_id FROM restaurante WHERE id = v_restaurante_id
    )
      AND tipo_endereco = 'comercial'
    LIMIT 1;

    v_distancia := SQRT(
        POWER(v_cliente_lat - v_rest_lat, 2) +
        POWER(v_cliente_lon - v_rest_lon, 2)
    );

    INSERT INTO pedido (
        cliente_id, restaurante_id, status, data_hora, taxa_entrega, valor_total
    )
    VALUES (
        v_cliente_id,
        v_restaurante_id,
        (SELECT id FROM status_de_pedido WHERE status = 'Pendente' LIMIT 1),
        NOW(),
        NULL,
        45.00
    )
    RETURNING id INTO v_pedido_id;

    INSERT INTO pedido_itens (pedido_id, produto_id, quantidade)
    VALUES (v_pedido_id, v_produto_id, 1);

    INSERT INTO pagamento (pedido_id, metodo_id, status_id)
    VALUES (
        v_pedido_id,
        (SELECT id FROM metodo_pagamento WHERE metodo = 'Pix' LIMIT 1),
        (SELECT id FROM status_pagamento WHERE status = 'Pendente' LIMIT 1)
    );

    CALL calcular_taxa_entrega(v_distancia, v_taxa);

    UPDATE pedido
    SET taxa_entrega = v_taxa,
        valor_total = 45.00 + v_taxa
    WHERE id = v_pedido_id;
END;
$$;


-- ================================================================
-- MOMENTO 9 - ATRIBUICAO DO ENTREGADOR
-- ================================================================

DO $$
DECLARE
    v_pedido_id INTEGER;
BEGIN
    SELECT id INTO v_pedido_id
    FROM pedido
    ORDER BY id DESC
    LIMIT 1;

    CALL atribuir_entregador(v_pedido_id);
END;
$$;


-- ================================================================
-- MOMENTO 10 - EVOLUCAO DO PEDIDO E HISTORICO
-- ================================================================

DO $$
DECLARE
    v_pedido_id INTEGER;
BEGIN
    SELECT id INTO v_pedido_id
    FROM pedido
    ORDER BY id DESC
    LIMIT 1;

    UPDATE pedido
    SET status = (SELECT id FROM status_de_pedido WHERE status = 'Aceito')
    WHERE id = v_pedido_id;

    UPDATE pedido
    SET status = (SELECT id FROM status_de_pedido WHERE status = 'Em preparo')
    WHERE id = v_pedido_id;

    UPDATE pedido
    SET status = (SELECT id FROM status_de_pedido WHERE status = 'Saiu para entrega')
    WHERE id = v_pedido_id;

    UPDATE pedido
    SET status = (SELECT id FROM status_de_pedido WHERE status = 'Entregue')
    WHERE id = v_pedido_id;

    UPDATE pagamento
    SET status_id = (SELECT id FROM status_pagamento WHERE status = 'Pago')
    WHERE pedido_id = v_pedido_id;
END;
$$;


-- ================================================================
-- MOMENTO 11 - VALIDACOES DO FLUXO
-- ================================================================

SELECT
    p.nome AS cliente,
    r.nome AS restaurante,
    ped.data_hora,
    ped.taxa_entrega,
    ped.valor_total,
    s.status AS status_atual
FROM pedido ped
JOIN pessoa p ON p.pessoa_id = ped.cliente_id
JOIN restaurante r ON r.id = ped.restaurante_id
JOIN status_de_pedido s ON s.id = ped.status
ORDER BY ped.id DESC;

SELECT
    e.id AS entregador_id,
    pe.nome AS entregador,
    ped.id AS pedido_id
FROM pedido ped
LEFT JOIN entregador e ON e.id = ped.entregador_id
LEFT JOIN pessoa pe ON pe.pessoa_id = e.pessoa_id
ORDER BY ped.id DESC;

SELECT
    hp.id,
    hp.pedido_id,
    sa.status AS status_anterior,
    sn.status AS status_novo,
    hp.data_alteracao
FROM historico_pedido hp
JOIN status_de_pedido sa ON sa.id = hp.status_anterior_id
JOIN status_de_pedido sn ON sn.id = hp.status_novo_id
ORDER BY hp.id;


-- ================================================================
-- MOMENTO 11B - TRANSACAO E SQL AVANCADO
-- ================================================================

BEGIN;

SAVEPOINT sp_produtos_variados;

INSERT INTO produto (nome, tipo, preco, custo, restaurante_id)
VALUES ('Teste Temporario', 'Promoção', 1.00, 0.50,
        (SELECT id FROM restaurante WHERE nome = 'Pizzaria do Joao'));

ROLLBACK TO SAVEPOINT sp_produtos_variados;

WITH pedidos_por_cliente AS (
    SELECT
        ped.cliente_id,
        COUNT(*) AS total_pedidos,
        SUM(ped.valor_total) AS valor_total_cliente
    FROM pedido ped
    GROUP BY ped.cliente_id
),
ranking_entregadores AS (
    SELECT
        e.id AS entregador_id,
        pe.nome AS entregador,
        COUNT(ped.id) AS total_entregas,
        ROW_NUMBER() OVER (ORDER BY COUNT(ped.id) DESC, pe.nome) AS ranking
    FROM entregador e
    JOIN pessoa pe ON pe.pessoa_id = e.pessoa_id
    LEFT JOIN pedido ped ON ped.entregador_id = e.id
    GROUP BY e.id, pe.nome
)
SELECT
    p.nome AS cliente,
    pc.total_pedidos,
    pc.valor_total_cliente,
    re.entregador,
    re.total_entregas,
    re.ranking
FROM pedidos_por_cliente pc
JOIN pessoa p ON p.pessoa_id = pc.cliente_id
LEFT JOIN ranking_entregadores re ON re.ranking = 1
ORDER BY pc.valor_total_cliente DESC;

SELECT
    r.nome,
    r.status_funcionamento,
    c.nome AS cidade,
    e.latitude,
    e.longitude
FROM restaurante r
JOIN pessoa p ON p.pessoa_id = r.pessoa_id
JOIN endereco e ON e.id_pessoa = p.pessoa_id
JOIN cidade c ON c.id = e.cidade_id
WHERE r.status_funcionamento = TRUE
  AND EXISTS (
      SELECT 1
      FROM pedido ped
      WHERE ped.restaurante_id = r.id
        AND ped.valor_total > 40
  );

EXPLAIN ANALYZE
SELECT
    r.nome,
    c.nome AS cidade,
    e.cep
FROM restaurante r
JOIN pessoa p ON p.pessoa_id = r.pessoa_id
JOIN endereco e ON e.id_pessoa = p.pessoa_id
JOIN cidade c ON c.id = e.cidade_id
WHERE r.status_funcionamento = TRUE
  AND e.cep = '89460-100';

COMMIT;


-- ================================================================
-- MOMENTO 12 - TRIGGER DE BLOQUEIO
-- ================================================================

DO $$
DECLARE
    v_restaurante_id INTEGER;
    v_cliente_id     INTEGER;
BEGIN
    SELECT id INTO v_restaurante_id
    FROM restaurante
    WHERE nome = 'Pizzaria do Joao';

    SELECT pessoa_id INTO v_cliente_id
    FROM pessoa
    WHERE cpf_cnpj = '11111111111';

    UPDATE restaurante
    SET status_funcionamento = FALSE
    WHERE id = v_restaurante_id;

    BEGIN
        UPDATE pedido
        SET status = (SELECT id FROM status_de_pedido WHERE status = 'Aceito' LIMIT 1)
        WHERE cliente_id = v_cliente_id
          AND restaurante_id = v_restaurante_id;
    EXCEPTION
        WHEN OTHERS THEN
            RAISE NOTICE 'Bloqueio esperado pela trigger: %', SQLERRM;
    END;

    UPDATE restaurante
    SET status_funcionamento = TRUE
    WHERE id = v_restaurante_id;
END;
$$;


-- ================================================================
-- MOMENTO 13 - EXPLAIN ANALYZE
-- ================================================================
-- precisa de pelo menos 3 EXPLAIN de consultas criticas (o primeiro ja ta
-- la em cima no Momento 11B, esses dois aqui completam os 3)

-- EXPLAIN 2: busca entregadores disponiveis (testa o idx_entregador_disponivel)
EXPLAIN ANALYZE
SELECT
    e.id                AS entregador_id,
    p.nome              AS nome_entregador,
    e.latitude,
    e.longitude
FROM entregador e
JOIN pessoa p ON p.pessoa_id = e.pessoa_id
WHERE e.disponivel = TRUE
ORDER BY e.id;

-- EXPLAIN 3: lista pedidos de um cliente (testa o idx_pedido_cliente, sem full scan)
EXPLAIN ANALYZE
SELECT
    ped.id              AS pedido_id,
    r.nome              AS restaurante,
    s.status            AS status_pedido,
    ped.valor_total,
    ped.taxa_entrega,
    ped.data_hora
FROM pedido ped
JOIN restaurante r        ON r.id = ped.restaurante_id
JOIN status_de_pedido s   ON s.id = ped.status
WHERE ped.cliente_id = (SELECT pessoa_id FROM pessoa WHERE cpf_cnpj = '11111111111')
ORDER BY ped.data_hora DESC;

-- atualiza a view materializada agora que ja tem dados
REFRESH MATERIALIZED VIEW CONCURRENTLY desempenho_entregadores;
