# Analise de access.log -- Paulo Henrique (@paulohenrique64)

**Linhas analisadas:** 516866

## 1. Volume e falha

```bash
awk '{ print $9 }' dados/access.log \
  | sort | uniq -c | sort -rn \
  | awk '
      { qtd[$2] = $1; codigo[NR] = $2; total += $1
        if ($2 ~ /^4/) e4 += $1
        if ($2 ~ /^5/) e5 += $1 }
      END {
        printf "Total de requisicoes : %d\n", total
        printf "Erros 4xx            : %d (%.2f%%)\n", e4, e4 * 100 / total
        printf "Erros 5xx            : %d (%.2f%%)\n", e5, e5 * 100 / total
        print ""
        for (i = 1; i <= NR; i++)
          printf "  %s %7d (%.2f%%)\n", codigo[i], qtd[codigo[i]], qtd[codigo[i]] * 100 / total
      }'
```

```
Total de requisicoes : 516866
Erros 4xx            : 6162 (1.19%)
Erros 5xx            : 11749 (2.27%)

  200  498955 (96.53%)
  503    6900 (1.33%)
  500    4849 (0.94%)
  404    4501 (0.87%)
  403    1661 (0.32%)
```

**Leitura:** De 516.866 requisicoes, 17.911 falharam -- 3,47% do total. O peso esta do lado do
servidor: 11.749 erros 5xx (2,27%) contra 6.162 erros 4xx (1,19%). Acima de 2% de 5xx ja e
incidente, nao operacao normal, e quem lidera e o `503` com 6.900 ocorrencias.

A contagem sai do campo `$9`, nao do texto da linha. A diferenca aparece no `grep` solto:

```bash
grep -c ' 500 ' dados/access.log
```

```
4921
```

Sao 72 linhas a mais que os 4.849 erros 500 reais: respostas bem-sucedidas cujo tamanho (`$10`)
era de 500 bytes.

## 2. Os 10 IPs mais frequentes

```bash
awk '{ print $1 }' dados/access.log | sort | uniq -c | sort -rn | head -10
```

```
  88400 203.0.113.47
   1788 192.0.2.245
   1772 192.0.2.171
   1771 192.0.2.81
   1771 192.0.2.225
   1771 192.0.2.16
   1767 192.0.2.138
   1762 192.0.2.222
   1757 192.0.2.45
   1753 192.0.2.166
```

O primeiro colocado esta 50x acima do segundo. Perfil do que ele pediu:

```bash
grep '^203\.0\.113\.47 ' dados/access.log \
  | awk '{ print "caminho", $7; print "status ", $9; print "agente ", $NF }' \
  | sort | uniq -c | sort -rn
```

```
  88400 agente  "curl/8.5.0"
  81500 status  200
  22224 caminho /api/busca?q=mochila
  22161 caminho /api/busca?q=tenis
  22090 caminho /api/busca?q=camiseta
  21925 caminho /api/busca?q=fone
   6900 status  503
```

E em que ritmo:

```bash
grep '^203\.0\.113\.47 ' dados/access.log \
  | awk '{ print $4 }' | cut -d: -f2-4 \
  | sort | uniq -c | sort -rn \
  | awk '
      { segundos++; total += $1; if (NR == 1) pico = $1 " req em " $2 }
      END {
        printf "segundos com trafego : %d\n", segundos
        printf "media                : %.2f req/s\n", total / segundos
        printf "pico                 : %s\n", pico
      }'
```

```
segundos com trafego : 7198
media                : 12.28 req/s
pico                 : 33 req em 23:24:01
```

**Leitura:** O 203.0.113.47 responde sozinho por 88.400 requisicoes -- 17,10% do log e cerca de
50x o segundo colocado. Todas cabem entre 22h e 23h59: 12,28 req/s de media, pico de 33 req/s e
trafego em 7.198 dos 7.200 segundos da janela, sem a pausa que um humano faz.

Nao e gente, e script. User-agent unico `curl/8.5.0`, quatro URLs fixas do endpoint mais caro
(`/api/busca?q=`) em rodizio, e nenhum CSS ou JS pedido junto -- navegador real sempre pede.

E o fecho da investigacao: os 6.900 `503` que ele levou sao exatamente todos os 503 do log
inteiro (pergunta 1). A saturacao do servico comeca e termina nesse IP.

## 3. O endpoint quebrado

```bash
awk '{ total[$7]++ }
     $9 == 500 { erro[$7]++ }
     END { for (c in erro)
             printf "%6d %8d %6.2f%%  %s\n", erro[c], total[c], erro[c] * 100 / total[c], c }' \
     dados/access.log \
  | sort -rn | head -5
```

```
  3620    10400  34.81%  /api/relatorio/gerar
   228    71682   0.32%  /
   167    52100   0.32%  /api/produtos
   160    58793   0.27%  /produtos
   150    45541   0.33%  /produtos/detalhe
```

As colunas sao: erros 500, total de requisicoes do caminho e a taxa de falha dele.

**Leitura:** `/api/relatorio/gerar` causou 3.620 erros 500, mais do que todos os outros caminhos
somados. Sao 34,81% das suas proprias 10.400 chamadas, contra cerca de 0,3% em todo o resto do
site -- que e apenas o ruido de fundo.

Ou seja, ele nao quebra sempre: quebra cerca de 1 vez a cada 3. Uma taxa alta mas intermitente
aponta para bug ou dependencia instavel (timeout, lock, memoria), nao para um endpoint fora do ar.

## 4. A hora do pico

```bash
awk '
  { split($4, t, ":"); h = t[2]; total[h]++; geral++
    if ($1 != "203.0.113.47") sembot[h]++ }
  END {
    for (h in total) if (total[h] > max) max = total[h]
    for (h in total) {
      barra = sprintf("%*s", int(total[h] * 40 / max), ""); gsub(/ /, "#", barra)
      printf "%sh %6d %6d %6.2f%%  %s\n", h, total[h], sembot[h], total[h] * 100 / geral, barra
    }
  }' dados/access.log | sort
```

Colunas: hora, total, total sem o 203.0.113.47 e percentual do dia.

```
00h   3262   3262   0.63%  #
01h   1967   1967   0.38%  #
02h   1810   1810   0.35%  #
03h   1471   1471   0.28%  
04h   1498   1498   0.29%  
05h   1844   1844   0.36%  #
06h   3904   3904   0.76%  ##
07h   9759   9759   1.89%  #####
08h  19519  19519   3.78%  ###########
09h  27621  27621   5.34%  ################
10h  30869  30869   5.97%  ##################
11h  32526  32526   6.29%  ##################
12h  31895  31895   6.17%  ##################
13h  29952  29952   5.79%  #################
14h  31225  31225   6.04%  ##################
15h  32529  32529   6.29%  ##################
16h  30886  30886   5.98%  ##################
17h  28575  28575   5.53%  ################
18h  25996  25996   5.03%  ###############
19h  22807  22807   4.41%  #############
20h  18860  18860   3.65%  ###########
21h  15577  15577   3.01%  #########
22h  43979  13039   8.51%  #########################
23h  68535  11075  13.26%  ########################################
```

**Leitura:** O pico e as 23h, com 68.535 requisicoes -- 13,26% do dia. Mas ele e artificial: sem o
203.0.113.47 sobram 11.075, o que faria das 23h uma das horas mais calmas, e as 22h caem de
43.979 para 13.039.

A coluna sem o bot revela o trafego real, com forma de jornada humana: vale de 1.471 as 3h,
subida a partir das 7h, plato entre 10h e 16h e pico legitimo as 15h com 32.529 requisicoes.

## 5. Alguem batendo na porta

```bash
awk '$7 ~ /admin|\.env|\.git|wp-login|phpmyadmin/ {
       split($4, t, ":")
       print "caminho " $7
       print "status  " $9
       print "ip      " $1
       print "agente  " $NF
       print "hora    " t[2] "h" }' dados/access.log \
  | sort | uniq -c | sort -k2,2 -k1,1rn
```

```
   2080 agente  "python-requests/2.32.3"
    382 caminho /admin/login
    368 caminho /wp-login.php
    356 caminho /.git/config
    343 caminho /.env
    318 caminho /phpmyadmin/index.php
    313 caminho /admin
    547 hora    05h
    518 hora    02h
    518 hora    04h
    497 hora    03h
   1053 ip      198.51.100.9
   1027 ip      198.51.100.23
   2080 status  404
```

Os dois IPs fizeram alguma outra coisa no site durante o dia?

```bash
grep -cE '^198\.51\.100\.(9|23) ' dados/access.log
```

```
2080
```

**Leitura:** Sim, ha. Foram 2.080 tentativas contra os seis caminhos sensiveis, vindas de apenas
2 IPs: 198.51.100.9 (1.053) e 198.51.100.23 (1.027). O servidor respondeu `404` as 2.080 --
nenhum `200`, nada exposto.

O perfil e de varredura automatizada: `python-requests/2.32.3` nos dois, atividade so entre 2h e
5h e ritmo lento e regular de cerca de 520 por hora, discreto o bastante para nao disparar alarme.

O ultimo comando fecha o caso: os dois IPs fizeram 2.080 requisicoes no dia inteiro, exatamente as
2.080 tentativas. 100% do que pediram era caminho sensivel -- nao navegaram no site, so bateram
nas portas.

## Conclusao: minha primeira acao como operador de plantao

Bloquearia o 203.0.113.47 agora, com regra de firewall ou rate limit no proxy, antes de qualquer
outra coisa. A justificativa esta em tres numeros desta analise: ele sozinho e 17,10% do trafego
do dia, vindo de 1 endereco entre 257; sustentou 12,28 req/s por duas horas seguidas contra as
quatro URLs mais caras do site; e os 6.900 `503` que provocou sao 100% dos 503 do log, ou seja,
ele e o unico motivo pelo qual usuarios reais viram o servico indisponivel as 23h. Bloquear
devolve capacidade ao trafego legitimo em segundos, nao exige deploy e nao depende de acordar
ninguem -- o que importa as 23h.

Feito isso, ainda na mesma madrugada, abriria incidente para `/api/relatorio/gerar`: 34,81% de
falha nas 10.400 chamadas, taxa que se mantem estavel o dia todo e portanto nao tem relacao com o
ataque. Esse e bug de aplicacao e precisa do time de desenvolvimento, nao de firewall. Os dois
varredores (198.51.100.9 e 198.51.100.23) entram na lista de bloqueio tambem, mas sem pressa:
levaram 404 em 100% das 2.080 tentativas, entao sao ruido, nao incidente. O que eu nao faria as
23h e reverter deploy -- nada nos dados aponta para mudanca recente, ja que a taxa de erro do
endpoint quebrado e a mesma as 3h e as 15h.
