# Nosso Amigo Secreto 2026

React + TypeScript + Tailwind CSS, com Supabase Auth e PostgreSQL. A versão sem configuração exibe a experiência natalina, mas bloqueia login, sorteio e persistência remota. Nenhum resultado é simulado ou guardado no navegador.

## Ativar o evento real

1. Crie um projeto em https://supabase.com/dashboard. Execute `supabase/schema.sql` uma única vez no SQL Editor.
2. Em Authentication, desative novos cadastros públicos. Adicione/invite os cinco usuários pelos e-mails reais e configure SMTP para entrega confiável de links de acesso.
3. Em Authentication → URL Configuration, defina a URL final em Site URL e na lista de Redirect URLs.
4. Vincule cada UUID de Authentication ao perfil correto no SQL Editor (não use e-mails inventados):

```sql
update public.participants set user_id='UUID-REAL-DE-SAMUEL', is_admin=true where name='Samuel';
update public.participants set user_id='UUID-REAL-DE-GABI' where name='Gabi';
update public.participants set user_id='UUID-REAL-DE-GABRIEL' where name='Gabriel';
update public.participants set user_id='UUID-REAL-DE-MIRELLA' where name='Mirella';
update public.participants set user_id='UUID-REAL-DE-VANESSA' where name='Vanessa';
```

5. Copie `.env.example` para `.env.local` e preencha URL e chave pública anon/publishable. Nunca coloque `service_role` no frontend. As variáveis `VITE_` são públicas e incorporadas durante o build.
6. Rode `npm install`, `npm run build`. Publique `dist/`. No Sites, será preciso reconstruir e publicar uma versão com a configuração pública incorporada. A publicação inicial do Sites é privada ao proprietário; ajuste o acesso do site para os participantes antes de distribuir o convite.
7. Entre como Samuel, abra a engrenagem em Nosso encontro, salve data/local/valores e confirme o sorteio definitivo. Não execute antes de revisar os cinco vínculos.

## Segurança e persistência

- Autenticação por link de e-mail; não existe troca de perfil por nome.
- Perfis só podem ser lidos pelo próprio usuário, sem permissão de alteração de identidade ou administrador.
- Tabela de resultados sem privilégios para `anon` ou `authenticated`. A função `my_result()` não recebe IDs: usa exclusivamente `auth.uid()` e retorna apenas o destinatário e seus desejos.
- Lista de desejos editável e consultável diretamente somente pelo proprietário; quem o tirou recebe os desejos via função restrita.
- `draw_once()` exige administrador, bloqueia a linha do evento e grava todo o grupo na mesma transação. Fisher-Yates com bytes criptográficos, rejeição de viés e rejeição de permutações com autoatribuição. Chaves únicas garantem destinatários e remetentes exclusivos.
- A API de configuração não permite escrever o indicador `drawn`. Não há função de reset.
- Administradores do banco/Supabase continuam tecnicamente capazes de acessar os dados, como em qualquer implantação administrada.
- Resultados e desejos persistem no Supabase. A sessão utiliza a persistência do SDK; resultados não são salvos em localStorage.

## Validação antes do uso

Em um projeto de teste, autentique duas contas distintas: cada uma deve receber apenas seu próprio perfil/resultado. Leituras diretas de assignments devem falhar; leitura dos desejos alheios deve retornar vazio; chamadas de sorteio por não administrador devem falhar. Duas chamadas simultâneas de sorteio devem gerar um único conjunto de cinco resultados. Uma segunda tentativa deve falhar. Atualize a página e confirme a persistência da lista. Teste o login por e-mail em outro celular.

Esses testes de integração exigem um projeto Supabase ativo e não são substituídos pela compilação TypeScript. Referência: https://supabase.com/docs/guides/database/postgres/row-level-security e https://supabase.com/docs/guides/database/functions.

## Interface

Contagem até 25/12/2026, 00:00 em Brasília; encontro separado e configurável. Música sintetizada opcional, sem reprodução automática. Neve e animações respeitam a preferência de movimento reduzido. O WhatsApp recebe somente o convite e a URL, sem resultados.

## Fotos dos participantes

Fotos de identificação: Gabi (1), Mirella (2), Gabriel (3), Vanessa (4), Samuel (5), conforme enviadas. Arquivos estáticos em `public/participants/` contêm apenas as fotos. O recorte circular é feito por CSS, sem alterar os originais. A associação nome/foto é pública para quem tem acesso ao site e não contém UUIDs ou relações do sorteio. Atualizar esses arquivos não executa SQL, migrações ou funções de sorteio e não altera resultados. Preserve o acesso privado do site ao compartilhar fotos apenas com o grupo.

## GitHub Pages

Versão preparada para publicação em subdiretório no GitHub Pages: assets e fotografias usam caminhos relativos, e o convite e retorno de login usam a URL completa do aplicativo. Publique a pasta `docs/` da branch principal. Recompile com `npm run build` e copie `dist/` para `docs/` a cada alteração. A autenticação e os resultados secretos continuam no Supabase; GitHub Pages hospeda apenas arquivos estáticos. Não publique chaves service_role nem resultados no repositório.

## Render — hospedagem gratuita

O `render.yaml` cria apenas um Static Site gratuito, usando a branch `main`, build `npm ci && npm run build` e diretório público `dist`. Não cria serviço Node pago, disco ou banco. O Render escolhe o endereço `onrender.com` disponível ao criar o site. No painel Render, use New → Blueprint e selecione este repositório, ou New → Static Site com os mesmos comandos. Confirme que a configuração é Static Site.

O tema natural e as cinco fotos são mantidos. A interface funciona no domínio raiz sem mudanças na lógica do sorteio. O site anterior no GitHub Pages deve continuar disponível até o novo endereço ser verificado.

Esta mudança hospeda a interface; não ativa o login ou envio de e-mail. Para ativá-los, configure Supabase, vincule os cinco e-mails e adicione `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` como variáveis de build no Render. Configure a nova URL em Authentication → URL Configuration do Supabase e publique novamente. Use somente a chave pública publishable/anon; nunca service_role. Resultados e desejos permanecem no banco remoto, sem depender de disco temporário do Render. Nenhum sorteio é executado durante o build ou a implantação.
