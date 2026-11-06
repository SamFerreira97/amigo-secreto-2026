# Nosso Amigo Secreto 2026

React, TypeScript, Tailwind CSS e Supabase. Interface publicada em https://amigo-secreto-2026-149q.onrender.com/.

## Cadastro individual

Cada pessoa informa seu e-mail, recebe um link, confirma a conta e usa um convite individual para vincular seu perfil. Não há escolha livre de nome e não é necessário cadastrar os cinco e-mails antecipadamente. Uma conta pode ter apenas um perfil; um perfil vinculado não pode ser tomado por outra conta.

Somente o organizador gera os convites, em **Nosso encontro → engrenagem → Convites individuais**. Compartilhe cada código diretamente com a pessoa indicada. Valem 30 dias, são de uso único e não contêm resultados. Gerar outro invalida o convite anterior ainda não utilizado.

## Ativar o Supabase

1. Crie um projeto gratuito. Execute `supabase/schema.sql` uma única vez no banco novo, seguido de `supabase/002_enrollment.sql`.
2. Habilite autenticação por e-mail e cadastro de novos usuários, mantendo a confirmação de e-mail. O app solicita `shouldCreateUser: true`; contas sem convite não recebem perfil nem resultados.
3. Configure Site URL e Redirect URLs para `https://amigo-secreto-2026-149q.onrender.com/`, sem curingas desnecessários.
4. Configure Custom SMTP: Gmail `smtp.gmail.com`, porta `587` (STARTTLS), usuário e remetente iguais ao seu Gmail, nome `Nosso Amigo Secreto 2026`. O proprietário deve criar uma senha de app elegível na conta Google com verificação em duas etapas e inseri-la diretamente no Supabase. Não use a senha normal da conta. A credencial SMTP nunca deve entrar no código, GitHub ou variáveis VITE.
5. No template Magic Link, use assunto `Seu acesso ao Amigo Secreto 2026` e botão apontando para `{{ .ConfirmationURL }}`. Não inclua o resultado do sorteio.
6. No Render, defina `VITE_SUPABASE_URL` e `VITE_SUPABASE_ANON_KEY` com URL e chave pública publishable/anon. Reconstrua e publique. Nunca use service_role no frontend.
7. Execute `supabase/bootstrap-organizador.sql` no SQL Editor privado. Guarde o convite retornado somente para Samuel. Não execute automaticamente em builds. Reexecutar pode substituir um convite de Samuel ainda não usado; não altera resultados.
8. Samuel informa seu e-mail no app, abre o link e cola o convite. Depois gera os convites de Gabi, Gabriel, Mirella e Vanessa no painel do evento.
9. Cada pessoa completa o cadastro. Somente após os cinco vínculos, o organizador confirma o sorteio definitivo.

Custom SMTP é necessário para enviar aos participantes fora da equipe administrativa do Supabase. Não conceda acesso à organização Supabase aos participantes para contornar esse limite.

## Segurança

- Resultados somente no banco. Não há permutação completa no frontend, mensagens ou URLs.
- `assignments` não concede leitura direta ao cliente. `my_result()` usa apenas `auth.uid()` e retorna um destinatário e seus desejos.
- RLS limita perfil e desejos ao próprio usuário. O participante não altera identidade nem `is_admin`.
- Hashes de convites ficam em `private.enrollment_invites`, sem grants ao cliente. Funções restritas validam e-mail confirmado, convite, validade e identidade antes de vincular.
- O sorteio exige organizador, bloqueio transacional e cinco identidades. Fisher-Yates usa bytes criptográficos com rejeição de viés e de permutações com autoatribuição. Constraints garantem unicidade. Não há função de reset.
- Cadastro, e-mail, fotos e implantação não executam o sorteio nem alteram relações existentes.
- Fotos de identificação em `public/participants/` são públicas conforme autorizado e não contêm resultados ou UUIDs.
- Administradores do banco/Supabase mantêm acesso técnico privilegiado ao banco; esse poder não é concedido aos participantes.

## Desenvolvimento e validação

```sh
npm ci
npm test
npm run build
npm run dev
```

O teste executa o SQL real em PostgreSQL via PGlite com pgcrypto e um esquema Auth de teste. Cobre e-mail confirmado, convites, validade, substituição, vínculo único, RLS, restrição administrativa, sorteio único e preservação dos resultados. Não testa entrega SMTP real.

Antes de liberar: testar entrega ao proprietário, identidade após clicar, sessão após atualizar e isolamento entre duas contas. Não executar um sorteio real apenas para testar e-mail.

## Hospedagem

Render: branch `main`, build `npm ci && npm run build`, pasta `dist`. `render.yaml` descreve somente Static Site gratuito, sem banco, disco ou execução pagos. O Supabase é separado. Variáveis VITE são incorporadas no build e exigem nova publicação após mudanças.

A cópia no GitHub Pages usa `docs/`; atualize esse diretório com o build correspondente para publicar nessa hospedagem. O endereço principal atual é o Render.
