# Nosso Amigo Secreto 2026

Aplicativo React + TypeScript + Tailwind, com Supabase PostgreSQL para autenticação simplificada, perfis, fotografias, desejos e sorteio. Publicação principal: https://amigo-secreto-2026-149q.onrender.com/

## Uso

1. O organizador entrega um PIN individual em particular a cada pessoa. Os códigos já existentes continuam válidos.
2. Samuel confirma seu PIN, entra no Painel administrativo e inicializa o sorteio único. A confirmação gera os cinco pares atomicamente no servidor, sem revelar os pares ao administrador.
3. Cada pessoa escolhe sua foto, confirma o PIN e revela seu presente uma única vez. Os desejos são opcionais.
4. Após revelar, o cartão sai da seleção pública. A área Acessar meu perfil mantém os cinco perfis disponíveis para consulta e edição, inclusive em outro celular, com o mesmo PIN. Retornar ao perfil não repete a revelação nem modifica o sorteio.
5. Desejos cadastrados depois aparecem automaticamente para a pessoa autorizada a consultá-los; há também atualização manual. Ninguém vê quem o sorteou.

## Administração

O painel de Samuel permite configurar data e horário de Brasília, local, valores e mensagem; trocar fotos; acompanhar participações e listas; inicializar a rodada e recuperar acessos. As fotografias são reduzidas a 512 x 512, convertidas em WebP e armazenadas no Supabase. Fotos JPG, PNG ou WebP de até 8 MB são aceitas na interface, com prévia antes de salvar. O servidor aceita até 300 KB de dados WebP por fotografia. As fotografias são públicas; os desejos e resultados são privados.

Os perfis possuem UUIDs permanentes e nomes fixos. Alterar uma fotografia não altera IDs ou resultados. A atualização das fotos passa por uma função exclusiva do administrador e entra no histórico. As imagens só são recarregadas quando a versão do diretório muda, evitando transferir fotografias repetidamente a cada sincronização.

Para recuperar o PIN de um participante, Samuel confirma a identidade em particular, seleciona Recuperar PIN no painel, registra o procedimento e confirma. Um código aleatório substitui o antigo, as sessões antigas são revogadas e a ação é auditada. O novo código aparece apenas no retorno da operação: copie e entregue em particular. Sorteio e participação permanecem intactos. O painel não permite trocar o próprio PIN de Samuel. Se o organizador perder o acesso, o proprietário do banco pode executar supabase/recuperar-administrador.sql no SQL Editor privado. Não execute esse arquivo durante uma publicação comum.

Não existe botão de reset, exclusão ou edição dos resultados. O histórico administrativo mostra ações e motivos de recuperação, nunca os pares sorteados ou PINs.

## Segurança

O PIN é um código aleatório de 32 caracteres hexadecimais (128 bits), adequado para copiar e colar no celular. Não são aceitos PINs numéricos curtos ou escolhidos pelo usuário. O servidor armazena apenas o hash SHA-256 do código de alta entropia; o código não fica no bundle, URL ou tabelas públicas. Após cinco erros no mesmo perfil, o servidor bloqueia novas tentativas por 15 minutos, inclusive em outros dispositivos. O contador persiste porque o RPC retorna um erro estruturado sem reverter a transação.

A validação emite uma sessão aleatória de 256 bits, com hash no banco e validade de 90 dias. Vários dispositivos podem ter sessões próprias sem se desconectar. localStorage contém somente a sessão deste dispositivo, nunca resultados ou todos os pares. Sair revoga essa sessão; o PIN continua permitindo novo acesso. A recuperação revoga todas as sessões do participante.

As funções identificam a pessoa pela sessão, sem aceitar um destinatário arbitrário. profile_state só devolve o resultado próprio já revelado, os desejos próprios e os desejos do destinatário atribuído. Antes de revelar não devolve o destinatário. As tabelas privadas não possuem privilégios para anon/authenticated e usam RLS. O esquema private não é exposto pela Data API. As antigas funções de sorteio e vinculação por e-mail estão revogadas.

initialize_code_draw exige a sessão administrativa e um bloqueio transacional na linha do evento. O sorteio usa Fisher-Yates criptográfico com amostragem por rejeição e rejeita permutações com autoatribuições. As constraints garantem um destinatário único por pessoa. reveal_secret apenas consulta a rodada pronta e registra a primeira participação, sob o mesmo bloqueio. Repetições falham. A inicialização também falha se já houver uma rodada.

A sincronização pública usa somente diretório, evento e status sem pares: Realtime com atualização adicional a cada cinco segundos. A lista privada do destinatário é consultada pelo RPC autorizado a cada cinco segundos enquanto estiver aberta e ao retornar à janela. Não há assinatura de tabelas privadas.

## Banco e publicação

Num projeto novo execute, nessa ordem: supabase/schema.sql, supabase/002_enrollment.sql, supabase/003_code_access.sql e supabase/004_permanent_profiles.sql. Num projeto existente, execute somente migrações ainda não aplicadas. A migração 004 preserva códigos, sessões válidas, fotos originais, desejos, participação e pares já existentes. Não execute as migrações novamente.

Num grupo novo execute supabase/gerar-codigos.sql uma única vez, no SQL Editor privado como proprietário. Guarde o retorno fora do repositório e entregue cada PIN em particular. O script não substitui códigos existentes. Nunca publique os códigos em arquivos versionados, variáveis VITE, URLs ou mensagens para o grupo. Os SQLs versionados não contêm PINs reais.

No Render use VITE_SUPABASE_URL e VITE_SUPABASE_ANON_KEY com a chave pública publishable. Nunca use service_role no frontend. Node 22.16.0; build npm ci && npm run build; pasta dist. SMTP não é necessário. Configure Cache-Control: no-cache, no-store, must-revalidate para a página inicial. O diretório docs é uma cópia histórica do GitHub Pages, não a publicação atual.

## Verificação

npm test executa testes das migrações e regras SQL reais com PostgreSQL/PGlite e pgcrypto: acesso dos cinco perfis, limites de tentativas persistentes, acesso permanente e em múltiplas sessões, migração de dados e sessões, inicialização administrativa, bloqueio de repetição, solicitações concorrentes enfileiradas, unicidade e autoatribuições, privacidade, desejos tardios, fotografias, recuperação auditada e preservação de IDs e pares. npm run build verifica TypeScript e gera a produção.

Para QA de navegador isolada, tests/browser-server.mjs fornece um banco SQL efêmero, somente em 127.0.0.1:54399. O Vite pode apontar temporariamente para essa URL e uma chave local de teste. Esse servidor e seus códigos previsíveis são exclusivamente de teste e nunca são usados pelo site publicado. A concorrência da produção é protegida por bloqueios PostgreSQL; o banco local PGlite serializa suas conexões. Não revele perfis reais apenas para testar uma publicação.
