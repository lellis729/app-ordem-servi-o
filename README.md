# Oficina | Gestão de serviços

Aplicação web responsiva para organizar clientes, equipamentos, ordens de serviço, estoque e financeiro. Pode ser publicada no GitHub Pages e instalada como app (PWA) em navegadores compatíveis.

## Executar localmente

Abra a pasta no VS Code e inicie um servidor HTTP local. Com Node.js instalado, por exemplo:

```bash
npx serve .
```

Acesse o endereço exibido no terminal. Para instalar o PWA, use HTTPS ou `localhost`; abrir `index.html` diretamente pelo sistema de arquivos não habilita o service worker.

## Publicar pelo GitHub Pages

1. Crie um repositório no GitHub e envie todos os arquivos deste projeto para a branch `main`.
2. Abra **Settings → Pages** no repositório e selecione **GitHub Actions** como fonte de publicação.
3. O workflow em `.github/workflows/pages.yml` publica o site a cada atualização da branch `main`. A URL estará na aba **Actions** ou em **Settings → Pages**.

Não é necessário compilar nem instalar dependências para publicar o site estático. O service worker e o manifesto já usam caminhos relativos para funcionar em repositórios de projeto no GitHub Pages.

## Dados e Supabase

O modo de demonstração guarda os dados no armazenamento local do navegador. Os dados não são enviados ao GitHub. Para usar uma base compartilhada com autenticação:

1. Crie um projeto no Supabase e execute `supabase/schema.sql` no SQL Editor.
2. Crie um usuário em **Authentication → Users** e associe seu UUID a um perfil `admin`, conforme o exemplo abaixo. Use um UUID novo para a empresa.

   ```sql
   insert into public.profiles (user_id, company_id, full_name, role)
   values ('UUID-DO-USUARIO', 'UUID-NOVO-DA-EMPRESA', 'Administrador', 'admin');
   ```

3. No app, abra **Configurações** e informe a URL do projeto e a chave pública `anon`/`publishable`.

Nunca publique uma chave `service_role`, senha ou arquivo `.env` no repositório. A chave pública foi feita para uso no navegador; mantenha as políticas RLS do schema habilitadas. Usuários adicionais precisam de perfil com o mesmo `company_id` e papel adequado.

## PWA e funcionamento offline

Após a primeira visita online, o service worker mantém em cache a interface e os arquivos locais do app. O uso offline não sincroniza com o Supabase e bibliotecas externas, como PDF, podem exigir internet.