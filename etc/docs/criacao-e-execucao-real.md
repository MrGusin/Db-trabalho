# Criação e execução real do banco

Este documento separa o que entra na base que você realmente usa no banco.

Use como referência estas partes do script unificado em [delivery.sql](../delivery.sql):

- Parte 1: schema e tabelas
- Parte 2: procedures, triggers e views
- Parte 5: segurança, roles, grants e RLS
- Parte 6: índices e otimização

O que não entra aqui:

- Parte 3: DML, seeds e transações de teste
- Parte 4: SQL avançado de demonstração
- Consultas de validação e `EXPLAIN ANALYZE` usados só para comparar planos

Se você quiser, o próximo passo pode ser transformar isso em um arquivo `.sql` separado só com esses blocos.