# Paulo Henrique Ribeiro Alves

- **GitHub:** @paulohenrique64
- **Curso e periodo:** Ciência da Computação, 8o período
- **Linguagem que voce domina melhor:** Java
- **Ja usou Linux no dia a dia?** sim
- **Ja usou Docker?** sim
- **O que voce espera desta disciplina:** Espero compreender mais profundamente a cultura DevOps, absorver os principais fundamentos da área e me familiarizar com as práticas e ferramentas mais utilizadas atualmente no mercado de trabalho (Kubernetes, Istio e Grafana).

## Diagnostico DORA do meu ultimo projeto

Pense no **ultimo projeto de software que voce entregou** — Projeto Monolítico de bots de RPA (consulta e verificação de documentos fiscais) da empresa onde faço estágio no momento.

Atualmente, existe uma esteira de CI/CD no GitLab interno da empresa. A cada Merge Request aprovada no repositório de DEV, é gerada uma nova tag seguindo o versionamento SemVer, e o bot fica pronto para ser implantado no ambiente de DEV com apenas um clique, para que possa ser testado pela equipe de testes.

Após a aprovação dos testes, basta clicar em outro botão para que o bot seja implantado em todos os containers de PROD. Tanto a implantação em DEV quanto em PROD leva menos de uma hora.

- **Frequencia de implantacao:** quantas vezes aquele software foi para
  "producao" (entregue funcionando para alguem usar)?

  Ao final de cada dia de trabalho, em média. Como se trata de um projeto de RPA, é comum haver alterações nos bots diariamente.

- **Lead time para mudancas:** quanto tempo passava, tipicamente, entre voce
  escrever um trecho de codigo e ele estar disponivel para o usuario?

  Aproximadamente 1 dia de trabalho, considerando o tempo de desenvolvimento, testes manuais e implantação em produção. O processo de deploy em si leva menos de uma hora em DEV e menos de uma hora em PROD.

- **Tempo de restauracao:** quando algo quebrava na apresentacao ou em uso,
  quanto tempo levava para voltar a funcionar?

  Aproximadamente 1 a 3 dias de trabalho, considerando o tempo necessário para identificar o problema, implementar a correção, realizar os testes manuais e disponibilizá-la novamente em produção.

- **Taxa de falha em mudancas:** que proporcao das entregas quebrou algo que
  antes funcionava?

  Não é possível informar a taxa de falha em mudanças, pois os dados são internos e confidenciais da empresa. Quando ocorre uma falha, ela é identificada por meio de um dashboard no Grafana e dos logs do bot que falhou. Em seguida, é criada uma tarefa no Jira para correção, que normalmente leva de 1 a 3 dias para ser implementada, testada e disponibilizada em produção.

### Qual metrica era a pior, e por que

Lead time para mudanças e tempo de restauração, pois ambos são impactados pelo gargalo na etapa de testes, que ainda é realizada manualmente. Com a automação dos testes, seria possível executar uma série de casos de teste a cada modificação no bot, reduzindo significativamente o tempo do processo, que atualmente pode levar cerca de 1 dia de trabalho para apenas alguns minutos.
