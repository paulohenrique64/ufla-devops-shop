# Autopsia: Interrupção do banco de dados do GitLab (31 de janeiro de 2017)

**Autor:** Paulo Henrique Ribeiro Alves (@paulohenrique64)
**Fonte primaria:** https://about.gitlab.com/blog/postmortem-of-database-outage-of-january-31/
**Data de acesso:** 08/09/2026

## 1. O que aconteceu

No dia 31 de janeiro de 2017, um engenheiro de software do GitLab começou a configurar múltiplos servidores PostgreSQL para rodar no ambiente de staging. A ideia era testar o balanceamento de carga entre diferentes servidores PostgreSQL utilizando o Pgpool-II, visando melhorar a arquitetura atual, que era limitada a dois servidores PostgreSQL, um primário e outro secundário. Por volta das 17:20 UTC, um snapshot do banco PostgreSQL que estava rodando no ambiente de produção foi copiado para o ambiente de staging, para permitir testes com uma cópia mais atualizada do banco. Por volta das 19:00 UTC, o GitLab.com começou a receber uma carga maior no banco de dados, devido a spam e também a um processo que estava tentando remover um funcionário e seus dados. Por volta das 23:00 UTC, devido à grande carga no servidor primário, o processo de replicação com o servidor secundário começou a apresentar falhas. Um engenheiro tentou reconstruir manualmente o servidor secundário, mas o comando utilizado não apresentava nenhuma informação na tela e ele não sabia que esse comportamento era normal. Depois de receber essa informação de outro engenheiro, ele decidiu limpar os dados que acreditava serem do servidor secundário para tentar novamente, mas acabou executando o processo no servidor primário e apagando aproximadamente 300 GB de dados. Como os backups que deveriam ser utilizados para recuperação também estavam com problemas, foi necessário utilizar o snapshot criado às 17:20 UTC para recuperar o banco. Com isso, foram perdidos aproximadamente 6 horas de dados, e o GitLab.com só teve sua restauração finalizada por volta das 18:00 UTC do dia 1º de fevereiro, após aproximadamente 19 horas de indisponibilidade.

## 2. Qual das Tres Vias falhou

Os princípios do Aprendizado, visto que a organização não tinha aprendido com a necessidade de documentar corretamente os procedimentos de recuperação e sincronização dos servidores PostgreSQL. Isso se comprova pelo fato de que o comando de sincronização manual entre os servidores PostgreSQL (pg_basebackup) não estava completamente documentado nos documentos da empresa e, por azar dos engenheiros, nem na documentação original. Isso levou ao cancelamento da primeira execução do comando por não entender quais saídas o mesmo deveria apresentar e, posteriormente, à tentativa de limpar os dados antes de executá-lo novamente. Como o engenheiro não sabia que o comando poderia ficar aguardando sem apresentar informações na tela, acabou apagando sem querer os dados do servidor primário na segunda tentativa.

## 3. Quais metricas DORA teriam denunciado antes

Provavelmente a métrica Time to Restore Service, visto que a organização já possuía problemas relacionados à recuperação de seus servidores de banco de dados. Os procedimentos de recuperação não estavam devidamente estabelecidos, documentados e testados, tanto que ninguém era responsável por testar regularmente os backups. Isso faria com que o tempo necessário para restaurar o serviço após uma falha fosse elevado, e um Time to Restore Service alto em incidentes anteriores já poderia indicar que a organização tinha dificuldades para se recuperar de falhas. Portanto, essa métrica poderia ter denunciado antes do incidente que os processos de recuperação não eram eficientes o suficiente.

## 4. Qual pratica do semestre teria evitado -- e em que semana

Semana 4: Linux II: automação e rede. O processo manual de sincronização entre os servidores primário e secundário do banco de dados deveria ser automatizado e bem documentado. Dessa forma, seria possível reduzir a quantidade de comandos manuais executados pelos engenheiros durante uma situação de recuperação e diminuir a possibilidade de executar um comando no servidor errado. Isso poderia ter evitado que o engenheiro apagasse acidentalmente os dados do servidor primário.

## 5. A cultura do relatorio: generativa ou patologica?

Generativa.

"In the spirit of transparency we kept track of progress and notes in a publicly visible Google document. [...] The document in question was initially private to GitLab employees and contained name of the engineer who accidentally removed the data. While the name was added by the engineer themselves (and they had no problem with this being public), we will redact names in future cases as other engineers may not be comfortable with their name being published."

O fato da empresa ter mantido o progresso da recuperação do incidente em um documento público mostra uma preocupação com a transparência. Além disso, mesmo com o nome do engenheiro que apagou o banco tendo sido colocado no documento pelo próprio engenheiro, a empresa decidiu que iria remover os nomes em incidentes futuros, mostrando uma preocupação em não expor individualmente quem cometeu o erro.

"8. Why was the backup procedure not tested on a regular basis? - Because there was no ownership, as a result nobody was responsible for testing this procedure."

Além disso, o relatório reconhece diretamente que existia uma falha na definição de responsabilidades pelo processo de backup, em vez de atribuir o problema a uma pessoa específica. A empresa identifica a falta de ownership como uma das causas do incidente e, posteriormente, inclui como ação a definição de um responsável pela durabilidade dos dados.