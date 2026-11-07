# Nosso Amigo Secreto 2026

React, TypeScript, Tailwind e Supabase. Publicação principal: https://amigo-secreto-2026-149q.onrender.com/

## Acesso sem e-mail

O participante escolhe sua foto e confirma um código privado aleatório de 128 bits. Não há cadastro, e-mail ou Supabase Auth no novo fluxo. O código segue no corpo de uma requisição HTTPS, nunca na URL. O banco guarda apenas hashes SHA-256 de códigos e sessões. As fotos são públicas e independentes do sorteio.

open_profile valida código e nome e emite uma sessão de 256 bits por 90 dias. Outro acesso antes da revelação substitui a sessão anterior. O primeiro reveal_secret bloqueia a linha do evento, gera uma permutação uniforme sem autoatribuições com bytes criptográficos e grava os cinco pares. A mesma transação marca apenas o participante atual. Revelações seguintes usam o sorteio existente. Repetir a revelação falha, e um código consumido não abre outra sessão.

profile_state retorna somente o resultado próprio já revelado, os desejos da pessoa sorteada e os desejos próprios. O navegador guarda a sessão em localStorage, inclusive para recuperar uma resposta interrompida. Não apague seus dados após participar. Outro celular não poderá entrar com o código consumido. Quem obtiver um código ou sessão poderá acessar o perfil correspondente. Entregue os códigos individualmente.

A tabela pública participation_status contém apenas nome e conclusão. O Realtime transmite suas atualizações, com atualização adicional a cada cinco segundos e ao retornar à janela. Nenhuma associação, código ou sessão aparece na tabela pública, no bundle ou no canal. As tabelas private.code_assignments, private.profile_access e private.code_wishes não permitem acesso direto por clientes. As funções antigas de e-mail e sorteio foram revogadas.

Samuel configura o encontro pelo próprio acesso. Cada pessoa mantém até três desejos. O convite WhatsApp não contém códigos nem resultados.

## Banco e publicação

Em projeto novo, execute supabase/schema.sql, supabase/002_enrollment.sql e supabase/003_code_access.sql nessa ordem. Em projeto existente, aplique somente a migração ainda não executada. A terceira preserva associações e desejos antigos.

Execute supabase/gerar-codigos.sql privadamente como proprietário uma única vez. Guarde o retorno fora do repositório. O script não substitui códigos existentes nem altera resultados. Nunca publique os códigos em arquivos versionados, variáveis VITE, URLs ou mensagens para todo o grupo. O SQL versionado contém apenas o gerador.

No Render defina VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY com a chave pública publishable. Nunca use service_role no frontend. Build: npm ci && npm run build. Saída: dist. Node 22.16.0. SMTP não é necessário. docs é uma cópia histórica do GitHub Pages; o site atual está no Render.

## Validação

npm test verifica o SQL real com PostgreSQL/PGlite e pgcrypto: códigos, isolamento e rotação de sessões, RLS, bloqueio de repetição, invariantes e persistência do sorteio, desejos e permissões do organizador. npm run build verifica TypeScript e compila a aplicação. Os testes não sorteiam o grupo em produção.
