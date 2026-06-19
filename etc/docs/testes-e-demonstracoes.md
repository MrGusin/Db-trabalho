# Testes e demonstrações

Este documento agrupa o que serve para testar o banco ou demonstrar comportamento, mas não é necessário para a criação da base em produção.

Use como referência estas partes do script unificado em [delivery.sql](../delivery.sql):

- Parte 3: DML, seeds e transações
- Parte 4: SQL avançado
- Blocos de verificação e comparação da Parte 6

O que normalmente fica aqui:

- inserts de teste
- `DO $$ ... $$` com `SAVEPOINT`, `ROLLBACK` e chamadas de procedures
- consultas `EXPLAIN ANALYZE`
- queries de validação de histórico e índices

Se quiser, eu também posso transformar esse conteúdo em um `.sql` de testes separado.