// Vigia de fim de partida do Treinador TCG (Windows). Compilado na hora pelo
// ferramentas/vigia.ps1 (Add-Type, C# 5 do .NET Framework; o arquivo fica so
// com ASCII). O painel inicia o vigia e conversa com ele por linhas:
//   painel -> vigia (entrada): "registrado" quando o registro da partida chega.
//   vigia -> painel (saida): JSON por linha (eventos).
// O que ele faz: fotografa so a janela do Pokemon TCG Live (PrintWindow, que
// nao enxerga os avisos por cima), reconhece a tela de resultado (botao
// REGISTRO DE BATALHA + CONTINUAR) e o registro aberto (painel com o icone de
// exportar) por cor e forma, e desenha por cima do jogo um aviso em dois
// passos e, se ligada, uma barreira sobre o CONTINUAR. Nunca clica nem digita
// no jogo, nem le a memoria dele.
using System;
using System.Collections.Concurrent;
using System.Collections.Generic;
using System.Diagnostics;
using System.Drawing;
using System.Drawing.Drawing2D;
using System.Drawing.Imaging;
using System.Drawing.Text;
using System.Globalization;
using System.Runtime.InteropServices;
using System.Text;
using System.Threading;
using System.Windows.Forms;

namespace TreinadorTCG
{
    // ---- O que a foto mostra ------------------------------------------------
    public sealed class Deteccao
    {
        // 0 = nenhuma tela de interesse; 1 = tela de resultado (registro
        // fechado); 2 = registro aberto (com o icone de exportar).
        public int Tela;
        public Rectangle Botao;      // REGISTRO DE BATALHA
        public Rectangle Continuar;  // CONTINUAR (amarelo)
        public Rectangle Painel;     // painel do registro
        public Rectangle Exportar;   // icone de exportar
        public Rectangle Area;       // parte da janela com o jogo (sem faixas pretas)
        public string Motivo = "";
    }

    // ---- Reconhecimento por cor e forma (sem ler texto: vale em qualquer
    // idioma). Medidas proporcionais a altura da janela: o jogo escala a tela
    // pela altura. Referencia: 1920x1080.
    public static class Detector
    {
        public static Deteccao Analisar(Bitmap bmp)
        {
            int w = bmp.Width, h = bmp.Height;
            int[] px = Pixels(bmp);
            return Analisar(px, w, h);
        }

        public static int[] Pixels(Bitmap bmp)
        {
            Rectangle r = new Rectangle(0, 0, bmp.Width, bmp.Height);
            BitmapData dados = bmp.LockBits(r, ImageLockMode.ReadOnly, PixelFormat.Format32bppArgb);
            try
            {
                int[] px = new int[bmp.Width * bmp.Height];
                if (dados.Stride == bmp.Width * 4) Marshal.Copy(dados.Scan0, px, 0, px.Length);
                else for (int y = 0; y < bmp.Height; y++) Marshal.Copy(new IntPtr(dados.Scan0.ToInt64() + (long)y * dados.Stride), px, y * bmp.Width, bmp.Width);
                return px;
            }
            finally { bmp.UnlockBits(dados); }
        }

        public static bool Amarelo(int c)
        {
            int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
            return r > 185 && g > 145 && b < 125 && r - b > 100 && g - b > 75;
        }

        // Cinza bem escuro e neutro (botao, painel).
        public static bool Escuro(int c, int limite)
        {
            int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
            int mx = Math.Max(r, Math.Max(g, b)), mn = Math.Min(r, Math.Min(g, b));
            return mx < limite && mx - mn < 24;
        }

        public static bool Claro(int c, int limite)
        {
            int r = (c >> 16) & 255, g = (c >> 8) & 255, b = c & 255;
            return Math.Min(r, Math.Min(g, b)) > limite;
        }

        // Liga a explicacao das recusas em Deteccao.Motivo (testes e diagnostico).
        public static bool Explicar;
        static StringBuilder notas;

        static void Nota(string s)
        {
            if (notas != null && notas.Length < 600) notas.Append(s).Append("; ");
        }

        // Area em que o jogo desenha: sem as faixas pretas (janela de outro
        // formato). As medidas sao proporcionais a altura dessa area.
        public static Rectangle AreaUtil(int[] px, int w, int h)
        {
            int esq = 0, dir = w - 1, topo = 0, baixo = h - 1;
            while (esq < w / 3 && ColunaPreta(px, w, h, esq)) esq++;
            while (dir > w * 2 / 3 && ColunaPreta(px, w, h, dir)) dir--;
            while (topo < h / 3 && LinhaPreta(px, w, topo)) topo++;
            while (baixo > h * 2 / 3 && LinhaPreta(px, w, baixo)) baixo--;
            return new Rectangle(esq, topo, dir - esq + 1, baixo - topo + 1);
        }

        static bool ColunaPreta(int[] px, int w, int h, int x)
        {
            for (int y = 0; y < h; y += Math.Max(1, h / 64)) { int c = px[y * w + x]; if (((c >> 16) & 255) > 12 || ((c >> 8) & 255) > 12 || (c & 255) > 12) return false; }
            return true;
        }

        static bool LinhaPreta(int[] px, int w, int y)
        {
            for (int x = 0; x < w; x += Math.Max(1, w / 64)) { int c = px[y * w + x]; if (((c >> 16) & 255) > 12 || ((c >> 8) & 255) > 12 || (c & 255) > 12) return false; }
            return true;
        }

        public static Deteccao Analisar(int[] px, int w, int h)
        {
            notas = Explicar ? new StringBuilder() : null;
            Rectangle util = AreaUtil(px, w, h);
            Deteccao d;
            if (util.Width == w && util.Height == h) d = AnalisarArea(px, w, h);
            else
            {
                int[] sub = new int[util.Width * util.Height];
                for (int y = 0; y < util.Height; y++) Array.Copy(px, (util.Y + y) * w + util.X, sub, y * util.Width, util.Width);
                d = AnalisarArea(sub, util.Width, util.Height);
                d.Botao = Mover(d.Botao, util.Location);
                d.Continuar = Mover(d.Continuar, util.Location);
                d.Painel = Mover(d.Painel, util.Location);
                d.Exportar = Mover(d.Exportar, util.Location);
            }
            d.Area = util;
            if (notas != null) { d.Motivo = (d.Motivo + " | " + notas.ToString()).Trim(' ', '|'); notas = null; }
            return d;
        }

        static Rectangle Mover(Rectangle r, Point o)
        {
            if (r.IsEmpty) return r;
            return new Rectangle(r.X + o.X, r.Y + o.Y, r.Width, r.Height);
        }

        static Deteccao AnalisarArea(int[] px, int w, int h)
        {
            Deteccao d = new Deteccao();
            if (w < 320 || h < 180) { d.Motivo = "janela pequena"; return d; }
            Rectangle cont = AcharContinuar(px, w, h);
            if (cont.IsEmpty) { d.Motivo = "sem CONTINUAR"; return d; }
            Rectangle bot = AcharBotao(px, w, h, cont);
            if (bot.IsEmpty) { d.Motivo = "sem botao do registro"; return d; }
            d.Continuar = cont;
            d.Botao = bot;
            d.Tela = 1;
            int x0 = AcharPainel(px, w, h, bot);
            if (x0 >= 0)
            {
                Rectangle exp = AcharExportar(px, w, h, x0);
                if (!exp.IsEmpty)
                {
                    d.Painel = new Rectangle(x0, 0, w - x0, h);
                    d.Exportar = exp;
                    d.Tela = 2;
                }
                else d.Motivo = "painel sem icone de exportar";
            }
            return d;
        }

        // Barra amarela larga embaixo, perto do meio.
        static Rectangle AcharContinuar(int[] px, int w, int h)
        {
            int xa = (int)(w * 0.12), xb = (int)(w * 0.88);
            int ya = (int)(h * 0.70), yb = h - 1;
            int minQtd = (int)(h * 0.12);
            double larMin = h * 0.22, larMax = h * 0.75;
            Rectangle melhor = Rectangle.Empty;
            int inicio = -1, falhas = 0, eMin = int.MaxValue, eMax = -1;
            for (int y = ya; y <= yb + 1; y++)
            {
                bool ok = false;
                int qtd = 0, mn = int.MaxValue, mx = -1;
                if (y <= yb)
                {
                    int base0 = y * w;
                    for (int x = xa; x < xb; x++)
                    {
                        if (Amarelo(px[base0 + x])) { qtd++; if (x < mn) mn = x; if (x > mx) mx = x; }
                    }
                    int lar = mx - mn + 1;
                    ok = qtd >= minQtd && lar >= larMin && lar <= larMax && qtd >= 0.55 * lar;
                }
                if (ok)
                {
                    if (inicio < 0) { inicio = y; eMin = mn; eMax = mx; }
                    else { if (mn < eMin) eMin = mn; if (mx > eMax) eMax = mx; }
                    falhas = 0;
                    continue;
                }
                if (inicio >= 0 && ++falhas <= 1 && y <= yb) continue;
                if (inicio >= 0)
                {
                    int fim = y - falhas;
                    int alt = fim - inicio + 1;
                    if (alt >= h * 0.022 && alt <= h * 0.095)
                    {
                        Rectangle r = new Rectangle(eMin, inicio, eMax - eMin + 1, alt);
                        double cx = r.X + r.Width / 2.0;
                        bool perto = Math.Abs(cx - w / 2.0) <= w * 0.18;
                        if (perto && Preenchimento(px, w, r, 0) >= 0.6 && r.Width * r.Height > melhor.Width * melhor.Height) melhor = r;
                    }
                }
                inicio = -1; falhas = 0; eMin = int.MaxValue; eMax = -1;
            }
            return melhor;
        }

        // Botao escuro (com texto claro) acima do CONTINUAR, centralizado nele.
        static Rectangle AcharBotao(int[] px, int w, int h, Rectangle cont)
        {
            int cx = cont.X + cont.Width / 2;
            int ya = Math.Max(0, cont.Top - (int)(h * 0.32));
            int yb = cont.Top - (int)(h * 0.025);
            int meia = (int)(h * 0.30);
            int xa = Math.Max(0, cx - meia), xb = Math.Min(w, cx + meia);
            int folga = Math.Max(2, (int)(h * 0.035));
            int lenMin = (int)(h * 0.10), lenMax = (int)(h * 0.34);
            Rectangle melhor = Rectangle.Empty;
            int inicio = -1, falhas = 0, eMin = int.MaxValue, eMax = -1;
            for (int y = ya; y <= yb + 1; y++)
            {
                int s = -1, e = -1;
                if (y <= yb) CorridaEscura(px, w, y, xa, xb, cx, folga, out s, out e);
                bool ok = s >= 0 && (e - s + 1) >= lenMin && (e - s + 1) <= lenMax && Math.Abs((s + e) / 2.0 - cx) <= h * 0.05;
                if (ok)
                {
                    if (inicio < 0) { inicio = y; eMin = s; eMax = e; }
                    else { if (s < eMin) eMin = s; if (e > eMax) eMax = e; }
                    falhas = 0;
                    continue;
                }
                // A linha do texto (letras claras) pode quebrar a corrida: tolera
                // algumas linhas, proporcional ao tamanho.
                if (inicio >= 0 && ++falhas <= Math.Max(2, (int)(h * 0.012)) && y <= yb) continue;
                if (inicio >= 0)
                {
                    int fim = y - falhas;
                    int alt = fim - inicio + 1;
                    Rectangle r = new Rectangle(eMin, inicio, eMax - eMin + 1, alt);
                    if (alt >= h * 0.025 && alt <= h * 0.09)
                    {
                        double razao = r.Width / (double)r.Height;
                        if (razao < 2.2 || razao > 7.5) Nota("botao razao " + razao.ToString("0.0", CultureInfo.InvariantCulture) + " " + r);
                        else if (ValidarBotao(px, w, h, r) && (melhor.IsEmpty || r.Bottom > melhor.Bottom)) melhor = r;
                    }
                    else if (alt >= 3) Nota("botao altura " + alt + " " + r);
                }
                inicio = -1; falhas = 0; eMin = int.MaxValue; eMax = -1;
            }
            return melhor;
        }

        // Corrida de pixels escuros (juntando buracos ate "folga", como as
        // letras claras do texto) que passa pelo centro "cx".
        static void CorridaEscura(int[] px, int w, int y, int xa, int xb, int cx, int folga, out int s, out int e)
        {
            s = -1; e = -1;
            int b0 = y * w;
            int ini = -1, ult = -1;
            for (int x = xa; x < xb; x++)
            {
                if (!Escuro(px[b0 + x], 75)) continue;
                if (ini < 0) { ini = x; ult = x; continue; }
                if (x - ult - 1 <= folga) { ult = x; continue; }
                if (ini <= cx && ult >= cx) { s = ini; e = ult; return; }
                ini = x; ult = x;
            }
            if (ini >= 0 && ini <= cx && ult >= cx) { s = ini; e = ult; }
        }

        static bool ValidarBotao(int[] px, int w, int h, Rectangle r)
        {
            int escuros = 0, claros = 0, n = 0;
            for (int y = r.Top; y < r.Bottom; y++)
                for (int x = r.Left; x < r.Right; x++)
                {
                    int c = px[y * w + x]; n++;
                    if (Escuro(c, 75)) escuros++;
                    else if (Claro(c, 120)) claros++;
                }
            if (n == 0) return false;
            double fe = escuros / (double)n, fc = claros / (double)n;
            if (fe < 0.45 || fc < 0.01 || fc > 0.45) { Nota("botao cores escuros=" + fe.ToString("0.00", CultureInfo.InvariantCulture) + " claros=" + fc.ToString("0.000", CultureInfo.InvariantCulture) + " " + r); return false; }
            // Em volta (acima e abaixo) nao e escuro: e um botao, nao uma area escura.
            int faixa = Math.Max(3, (int)(h * 0.02));
            double acima = FracEscuros(px, w, new Rectangle(r.Left, Math.Max(0, r.Top - faixa - 2), r.Width, faixa));
            double abaixo = FracEscuros(px, w, new Rectangle(r.Left, Math.Min(h - faixa, r.Bottom + 2), r.Width, faixa));
            if (acima >= 0.4 || abaixo >= 0.4) { Nota("botao em area escura " + r); return false; }
            return true;
        }

        static double FracEscuros(int[] px, int w, Rectangle r)
        {
            int esc = 0, n = 0;
            for (int y = r.Top; y < r.Bottom; y++)
                for (int x = r.Left; x < r.Right; x += 2) { n++; if (Escuro(px[y * w + x], 75)) esc++; }
            return n == 0 ? 0 : esc / (double)n;
        }

        // Fracao de amarelos (modo 0) num retangulo.
        static double Preenchimento(int[] px, int w, Rectangle r, int modo)
        {
            int ok = 0, n = 0;
            for (int y = r.Top; y < r.Bottom; y += 2)
                for (int x = r.Left; x < r.Right; x += 2) { n++; if (Amarelo(px[y * w + x])) ok++; }
            return n == 0 ? 0 : ok / (double)n;
        }

        // Painel do registro: faixa escura do lado direito, da borda esquerda dele
        // ate o fim da janela, com o cabecalho escuro no topo.
        static int AcharPainel(int[] px, int w, int h, Rectangle bot)
        {
            int ya = (int)(h * 0.12), yb = (int)(h * 0.92);
            int xa = Math.Max(bot.Right + 4, (int)(w * 0.45)), xb = (int)(w * 0.93);
            int passo = Math.Max(1, h / 540);
            int dentro = Math.Max(3, (int)(h * 0.012)), fora = Math.Max(4, (int)(h * 0.02));
            for (int x = xa; x < xb; x += passo)
            {
                if (FracColunaEscura(px, w, x, ya, yb) < 0.85) continue;
                if (x + dentro >= w || FracColunaEscura(px, w, x + dentro, ya, yb) < 0.85) continue;
                if (x - fora >= 0 && FracColunaEscura(px, w, x - fora, ya, yb) >= 0.6) continue;
                // Cabecalho escuro de ponta a ponta (ate a borda direita).
                double cab = FracEscurosLimite(px, w, new Rectangle(x, Math.Max(0, (int)(h * 0.005)), w - x, Math.Max(2, (int)(h * 0.06))), 70);
                if (cab >= 0.6) return x;
            }
            return -1;
        }

        static double FracColunaEscura(int[] px, int w, int x, int ya, int yb)
        {
            int esc = 0, n = 0;
            for (int y = ya; y < yb; y += 3) { n++; if (Escuro(px[y * w + x], 85)) esc++; }
            return n == 0 ? 0 : esc / (double)n;
        }

        static double FracEscurosLimite(int[] px, int w, Rectangle r, int limite)
        {
            int esc = 0, n = 0;
            for (int y = r.Top; y < r.Bottom; y += 2)
                for (int x = r.Left; x < r.Right; x += 2) { n++; if (Escuro(px[y * w + x], limite)) esc++; }
            return n == 0 ? 0 : esc / (double)n;
        }

        // Icone de exportar: no cabecalho do painel, o segundo desenho claro
        // a partir da direita (o primeiro e o X de fechar).
        static Rectangle AcharExportar(int[] px, int w, int h, int x0)
        {
            int ya = 0, yb = Math.Max(4, (int)(h * 0.075));
            int xa = x0 + (w - x0) / 2;
            int folga = Math.Max(1, (int)(h * 0.006));
            int largMin = Math.Max(3, (int)(h * 0.010)), largMax = (int)(h * 0.065);
            int[] col = new int[w];
            for (int x = xa; x < w; x++)
                for (int y = ya; y < yb; y++) if (Claro(px[y * w + x], 150)) col[x]++;
            List<int[]> grupos = new List<int[]>();
            int fim = -1, ini = -1, vazio = 0;
            for (int x = w - 1; x >= xa - 1; x--)
            {
                bool tem = x >= xa && col[x] > 0;
                if (tem)
                {
                    if (fim < 0) fim = x;
                    ini = x; vazio = 0;
                    continue;
                }
                if (fim >= 0 && ++vazio <= folga && x >= xa) continue;
                if (fim >= 0) grupos.Add(new int[] { ini, fim });
                fim = -1; ini = -1; vazio = 0;
            }
            List<int[]> bons = new List<int[]>();
            foreach (int[] g in grupos)
            {
                int larg = g[1] - g[0] + 1;
                if (larg >= largMin) bons.Add(g);
            }
            if (bons.Count < 2) return Rectangle.Empty;
            int[] fechar = bons[0], exportar = bons[1];
            if (fechar[1] - fechar[0] + 1 > largMax || exportar[1] - exportar[0] + 1 > largMax) return Rectangle.Empty;
            // Os dois icones ficam juntos no canto direito.
            if (fechar[1] < w - (int)(h * 0.08) || fechar[0] - exportar[1] > (int)(h * 0.06)) return Rectangle.Empty;
            int topo = int.MaxValue, baixo = -1;
            for (int y = ya; y < yb; y++)
                for (int x = exportar[0]; x <= exportar[1]; x++)
                    if (Claro(px[y * w + x], 150)) { if (y < topo) topo = y; if (y > baixo) baixo = y; }
            if (baixo < 0) return Rectangle.Empty;
            return new Rectangle(exportar[0], topo, exportar[1] - exportar[0] + 1, baixo - topo + 1);
        }
    }

    // ---- Onde desenhar o aviso ------------------------------------------------
    public sealed class Plano
    {
        public int Etapa;            // 1 = clique em Registro; 2 = clique em Exportar; 3 = registrada
        public Rectangle Alvo;       // contorno (vazio na etapa 3)
        public Rectangle Cartao;
        public Point SetaDe, SetaAte;
        public bool TemSeta;
        public Rectangle Barreira;   // vazio se nao houver
        public float Escala;

        public string Chave()
        {
            return Etapa + "|" + Alvo + "|" + Cartao + "|" + Barreira;
        }
    }

    public static class Planejador
    {
        public static float EscalaDe(int altura)
        {
            float s = altura / 1080f;
            return Math.Max(0.45f, Math.Min(2.5f, s));
        }

        // area = tamanho da janela do jogo (coordenadas da janela).
        public static Plano Planejar(Deteccao d, Size area, int etapa, Rectangle cartaoAnterior, bool barreira)
        {
            Plano p = new Plano();
            p.Etapa = etapa;
            // Tamanho do aviso acompanha o jogo (sem as faixas pretas).
            float s = EscalaDe(d.Area.IsEmpty ? area.Height : Math.Min(area.Height, d.Area.Height));
            p.Escala = s;
            int margem = (int)(12 * s);
            int cartAlt = (int)(118 * s);
            if (etapa == 1 && !d.Botao.IsEmpty)
            {
                int cartLarg = (int)(500 * s);
                Rectangle b = d.Botao;
                p.Alvo = b;
                int vao = (int)(58 * s);
                int x = b.Right + vao, y = b.Top + b.Height / 2 - cartAlt / 2;
                if (x + cartLarg > area.Width - margem)
                {
                    x = b.Left - vao - cartLarg;
                    if (x < margem)
                    {
                        x = Math.Max(margem, Math.Min(area.Width - margem - cartLarg, b.Left + b.Width / 2 - cartLarg / 2));
                        y = b.Top - vao - cartAlt;
                        p.Cartao = new Rectangle(x, y, cartLarg, cartAlt);
                        p.SetaDe = new Point(b.Left + b.Width / 2, y + cartAlt);
                        p.SetaAte = new Point(b.Left + b.Width / 2, b.Top - (int)(10 * s));
                    }
                    else
                    {
                        p.Cartao = new Rectangle(x, y, cartLarg, cartAlt);
                        p.SetaDe = new Point(x + cartLarg, y + cartAlt / 2);
                        p.SetaAte = new Point(b.Left - (int)(12 * s), y + cartAlt / 2);
                    }
                }
                else
                {
                    p.Cartao = new Rectangle(x, y, cartLarg, cartAlt);
                    p.SetaDe = new Point(x, y + cartAlt / 2);
                    p.SetaAte = new Point(b.Right + (int)(12 * s), y + cartAlt / 2);
                }
                p.TemSeta = true;
            }
            else if (etapa == 2 && !d.Exportar.IsEmpty)
            {
                int cartLarg = (int)(460 * s);
                Rectangle e = d.Exportar;
                p.Alvo = e;
                int direita = Math.Min(area.Width - margem, e.Right + (int)(30 * s));
                int x = Math.Max(margem, direita - cartLarg);
                int y = e.Bottom + (int)(62 * s);
                p.Cartao = new Rectangle(x, y, cartLarg, cartAlt);
                int ax = e.Left + e.Width / 2;
                p.SetaDe = new Point(ax, y);
                p.SetaAte = new Point(ax, e.Bottom + (int)(14 * s));
                p.TemSeta = true;
            }
            else if (etapa == 3)
            {
                int cartLarg = (int)(460 * s);
                if (!cartaoAnterior.IsEmpty) p.Cartao = new Rectangle(cartaoAnterior.X, cartaoAnterior.Y, cartLarg, cartAlt);
                else if (!d.Botao.IsEmpty) p.Cartao = new Rectangle(Math.Min(area.Width - margem - cartLarg, d.Botao.Right + (int)(40 * s)), d.Botao.Top + d.Botao.Height / 2 - cartAlt / 2, cartLarg, cartAlt);
                else p.Cartao = new Rectangle(area.Width / 2 - cartLarg / 2, (int)(area.Height * 0.12), cartLarg, cartAlt);
            }
            if (barreira && etapa != 3 && !d.Continuar.IsEmpty)
            {
                Rectangle c = d.Continuar;
                int inf = (int)(6 * s);
                p.Barreira = new Rectangle(c.X - inf, c.Y - inf, c.Width + 2 * inf, c.Height + 2 * inf);
            }
            return p;
        }
    }

    // ---- Desenho -------------------------------------------------------------
    public static class Desenho
    {
        static readonly Color Amarelo = Color.FromArgb(242, 194, 27);
        static readonly Color Dourado = Color.FromArgb(185, 141, 0);
        static readonly Color Tinta = Color.FromArgb(28, 34, 48);
        static readonly Color VerdeFundo = Color.FromArgb(220, 245, 228);
        static readonly Color Verde = Color.FromArgb(46, 160, 90);
        static readonly Color VerdeEscuro = Color.FromArgb(25, 110, 60);

        public static string Fonte = "Segoe UI";

        static GraphicsPath Arredondado(RectangleF r, float raio)
        {
            GraphicsPath g = new GraphicsPath();
            float d = Math.Min(raio * 2, Math.Min(r.Width, r.Height));
            g.AddArc(r.X, r.Y, d, d, 180, 90);
            g.AddArc(r.Right - d, r.Y, d, d, 270, 90);
            g.AddArc(r.Right - d, r.Bottom - d, d, d, 0, 90);
            g.AddArc(r.X, r.Bottom - d, d, d, 90, 90);
            g.CloseFigure();
            return g;
        }

        static Graphics Preparar(Bitmap b)
        {
            Graphics g = Graphics.FromImage(b);
            g.SmoothingMode = SmoothingMode.AntiAlias;
            g.TextRenderingHint = TextRenderingHint.AntiAliasGridFit;
            g.PixelOffsetMode = PixelOffsetMode.HighQuality;
            g.Clear(Color.Transparent);
            return g;
        }

        // Texto que cabe na largura (diminui a fonte se precisar).
        static Font Caber(Graphics g, string texto, float tamanho, FontStyle estilo, float largura)
        {
            Font f = new Font(Fonte, tamanho, estilo, GraphicsUnit.Pixel);
            while (g.MeasureString(texto, f).Width > largura && tamanho > 8)
            {
                f.Dispose();
                tamanho -= 1;
                f = new Font(Fonte, tamanho, estilo, GraphicsUnit.Pixel);
            }
            return f;
        }

        // Primeiro texto da lista que cabe (o ultimo vai de qualquer jeito).
        static Font CaberUm(Graphics g, string[] textos, float tamanho, FontStyle estilo, float largura, out string escolhido)
        {
            for (int i = 0; i < textos.Length; i++)
            {
                Font f = Caber(g, textos[i], tamanho, estilo, largura);
                if (i == textos.Length - 1 || g.MeasureString(textos[i], f).Width <= largura) { escolhido = textos[i]; return f; }
                f.Dispose();
            }
            escolhido = textos[textos.Length - 1];
            return Caber(g, escolhido, tamanho, estilo, largura);
        }

        // Cena do aviso (contorno, seta e cartao) do tamanho da janela do jogo.
        public static Bitmap Aviso(Plano p, Size area)
        {
            Bitmap b = new Bitmap(Math.Max(1, area.Width), Math.Max(1, area.Height), PixelFormat.Format32bppArgb);
            using (Graphics g = Preparar(b))
            {
                float s = p.Escala;
                if (!p.Alvo.IsEmpty)
                {
                    RectangleF a = p.Alvo;
                    float inf = 8 * s;
                    RectangleF anel = new RectangleF(a.X - inf, a.Y - inf, a.Width + 2 * inf, a.Height + 2 * inf);
                    using (GraphicsPath gp = Arredondado(anel, 12 * s))
                    {
                        using (Pen fora = new Pen(Color.FromArgb(200, Tinta), 9 * s)) g.DrawPath(fora, gp);
                        using (Pen pen = new Pen(Amarelo, 5 * s)) g.DrawPath(pen, gp);
                    }
                }
                if (p.TemSeta) Seta(g, p.SetaDe, p.SetaAte, s);
                if (!p.Cartao.IsEmpty) Cartao(g, p, s);
            }
            return b;
        }

        static void Seta(Graphics g, Point de, Point ate, float s)
        {
            double ang = Math.Atan2(ate.Y - de.Y, ate.X - de.X);
            float ponta = 26 * s;
            PointF corpoFim = new PointF((float)(ate.X - ponta * 0.6 * Math.Cos(ang)), (float)(ate.Y - ponta * 0.6 * Math.Sin(ang)));
            PointF[] cabeca = new PointF[] {
                new PointF(ate.X, ate.Y),
                new PointF((float)(ate.X - ponta * Math.Cos(ang - 0.5)), (float)(ate.Y - ponta * Math.Sin(ang - 0.5))),
                new PointF((float)(ate.X - ponta * Math.Cos(ang + 0.5)), (float)(ate.Y - ponta * Math.Sin(ang + 0.5)))
            };
            using (Pen fora = new Pen(Tinta, 13 * s)) { fora.StartCap = LineCap.Round; g.DrawLine(fora, de, corpoFim); }
            using (Pen pen = new Pen(Amarelo, 7 * s)) { pen.StartCap = LineCap.Round; g.DrawLine(pen, de, corpoFim); }
            using (Pen contorno = new Pen(Tinta, 4 * s)) { contorno.LineJoin = LineJoin.Round; g.DrawPolygon(contorno, cabeca); }
            using (SolidBrush br = new SolidBrush(Amarelo)) g.FillPolygon(br, cabeca);
        }

        static void Cartao(Graphics g, Plano p, float s)
        {
            RectangleF r = p.Cartao;
            bool ok = p.Etapa == 3;
            Color fundo = ok ? VerdeFundo : Amarelo, borda = ok ? Verde : Dourado, texto = ok ? VerdeEscuro : Tinta;
            for (int i = 3; i >= 1; i--)
            {
                RectangleF sombra = new RectangleF(r.X + 2 * s, r.Y + (2 + 2 * i) * s, r.Width, r.Height);
                using (GraphicsPath gs = Arredondado(sombra, 16 * s))
                using (SolidBrush bs = new SolidBrush(Color.FromArgb(28, 0, 0, 0))) g.FillPath(bs, gs);
            }
            using (GraphicsPath gp = Arredondado(r, 16 * s))
            {
                using (SolidBrush bf = new SolidBrush(fundo)) g.FillPath(bf, gp);
                using (Pen pb = new Pen(borda, 4 * s)) g.DrawPath(pb, gp);
            }
            float raio = 26 * s, cx = r.X + 46 * s, cy = r.Y + r.Height / 2;
            using (SolidBrush bc = new SolidBrush(texto)) g.FillEllipse(bc, cx - raio, cy - raio, 2 * raio, 2 * raio);
            if (ok)
            {
                using (Pen pv = new Pen(fundo, 6 * s)) { pv.StartCap = LineCap.Round; pv.EndCap = LineCap.Round; pv.LineJoin = LineJoin.Round;
                    g.DrawLines(pv, new PointF[] { new PointF(cx - 12 * s, cy + 1 * s), new PointF(cx - 3 * s, cy + 11 * s), new PointF(cx + 13 * s, cy - 10 * s) }); }
            }
            else
            {
                string n = p.Etapa.ToString(CultureInfo.InvariantCulture);
                using (Font fn = new Font(Fonte, 30 * s, FontStyle.Bold, GraphicsUnit.Pixel))
                using (SolidBrush bn = new SolidBrush(fundo))
                {
                    SizeF tn = g.MeasureString(n, fn);
                    g.DrawString(n, fn, bn, cx - tn.Width / 2, cy - tn.Height / 2);
                }
            }
            string titulo, principal;
            if (p.Etapa == 1) { titulo = "Treinador TCG  -  passo 1 de 2"; principal = "Clique em Registro de Batalha"; }
            else if (p.Etapa == 2) { titulo = "Treinador TCG  -  passo 2 de 2"; principal = "Agora clique em Exportar"; }
            else { titulo = "Treinador TCG"; principal = "Partida registrada!"; }
            float tx = r.X + 86 * s, largura = r.Right - tx - 14 * s;
            using (Font ft = Caber(g, titulo, 19 * s, FontStyle.Bold, largura))
            using (Font fp = Caber(g, principal, 27 * s, FontStyle.Bold, largura))
            using (SolidBrush bt = new SolidBrush(texto))
            {
                g.DrawString(titulo, ft, bt, tx, r.Y + 20 * s);
                g.DrawString(principal, fp, bt, tx, r.Y + 48 * s);
            }
        }

        // Barreira sobre o CONTINUAR.
        public static Bitmap Barreira(Size tamanho, float s)
        {
            Bitmap b = new Bitmap(Math.Max(1, tamanho.Width), Math.Max(1, tamanho.Height), PixelFormat.Format32bppArgb);
            using (Graphics g = Preparar(b))
            {
                RectangleF r = new RectangleF(2 * s, 2 * s, tamanho.Width - 4 * s, tamanho.Height - 4 * s);
                using (GraphicsPath gp = Arredondado(r, 10 * s))
                {
                    using (SolidBrush bf = new SolidBrush(Color.FromArgb(242, 28, 34, 48))) g.FillPath(bf, gp);
                    using (Pen pb = new Pen(Amarelo, 3 * s)) g.DrawPath(pb, gp);
                }
                string l1, l2;
                float alt = r.Height, larg = r.Width - 16 * s;
                using (Font f1 = CaberUm(g, new string[] { "Antes: Registro de Batalha", "Antes: Registro" }, Math.Max(10, alt * 0.40f), FontStyle.Bold, larg, out l1))
                using (Font f2 = CaberUm(g, new string[] { "clique aqui para continuar sem registrar", "clique para continuar sem registrar", "clique para pular" }, Math.Max(8, alt * 0.22f), FontStyle.Regular, larg, out l2))
                using (SolidBrush b1 = new SolidBrush(Amarelo))
                using (SolidBrush b2 = new SolidBrush(Color.FromArgb(225, 228, 235)))
                {
                    SizeF t1 = g.MeasureString(l1, f1), t2 = g.MeasureString(l2, f2);
                    float total = t1.Height * 0.86f + t2.Height;
                    float y = r.Y + (r.Height - total) / 2;
                    g.DrawString(l1, f1, b1, r.X + (r.Width - t1.Width) / 2, y);
                    g.DrawString(l2, f2, b2, r.X + (r.Width - t2.Width) / 2, y + t1.Height * 0.86f);
                }
            }
            return b;
        }
    }

    // ---- Windows -------------------------------------------------------------
    public static class Nativo
    {
        public const int WS_EX_LAYERED = 0x80000, WS_EX_TRANSPARENT = 0x20, WS_EX_TOOLWINDOW = 0x80, WS_EX_NOACTIVATE = 0x08000000, WS_EX_TOPMOST = 0x8;
        public delegate bool EnumProc(IntPtr h, IntPtr l);
        [StructLayout(LayoutKind.Sequential)] public struct RECT { public int L, T, R, B; }
        [StructLayout(LayoutKind.Sequential)] public struct POINT { public int X, Y; public POINT(int x, int y) { X = x; Y = y; } }
        [StructLayout(LayoutKind.Sequential)] public struct SIZE { public int W, H; public SIZE(int w, int h) { W = w; H = h; } }
        [StructLayout(LayoutKind.Sequential, Pack = 1)] public struct BLENDFUNCTION { public byte Op, Flags, Alpha, Format; }
        [DllImport("user32.dll")] public static extern bool EnumWindows(EnumProc p, IntPtr l);
        [DllImport("user32.dll")] public static extern bool IsWindow(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsWindowVisible(IntPtr h);
        [DllImport("user32.dll")] public static extern bool IsIconic(IntPtr h);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetWindowText(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll", CharSet = CharSet.Unicode)] public static extern int GetClassName(IntPtr h, StringBuilder s, int n);
        [DllImport("user32.dll")] public static extern bool GetClientRect(IntPtr h, out RECT r);
        [DllImport("user32.dll")] public static extern bool ClientToScreen(IntPtr h, ref POINT p);
        [DllImport("user32.dll")] public static extern IntPtr GetForegroundWindow();
        [DllImport("user32.dll")] public static extern bool PrintWindow(IntPtr h, IntPtr hdc, uint f);
        [DllImport("user32.dll")] public static extern bool SetWindowPos(IntPtr h, IntPtr depois, int x, int y, int cx, int cy, uint f);
        [DllImport("user32.dll")] public static extern bool SetWindowDisplayAffinity(IntPtr h, uint a);
        [DllImport("user32.dll", SetLastError = true)] public static extern bool UpdateLayeredWindow(IntPtr h, IntPtr hdcDst, ref POINT dst, ref SIZE tam, IntPtr hdcSrc, ref POINT src, int key, ref BLENDFUNCTION bl, int flags);
        [DllImport("user32.dll")] public static extern IntPtr GetDC(IntPtr h);
        [DllImport("user32.dll")] public static extern int ReleaseDC(IntPtr h, IntPtr dc);
        [DllImport("gdi32.dll")] public static extern IntPtr CreateCompatibleDC(IntPtr dc);
        [DllImport("gdi32.dll")] public static extern bool DeleteDC(IntPtr dc);
        [DllImport("gdi32.dll")] public static extern IntPtr SelectObject(IntPtr dc, IntPtr obj);
        [DllImport("gdi32.dll")] public static extern bool DeleteObject(IntPtr obj);
        [DllImport("user32.dll")] public static extern bool SetProcessDpiAwarenessContext(IntPtr v);
        [DllImport("user32.dll")] public static extern bool SetProcessDPIAware();
        [DllImport("user32.dll")] public static extern bool ShowWindow(IntPtr h, int cmd);

        public static void PrepararDpi()
        {
            try { if (SetProcessDpiAwarenessContext(new IntPtr(-4))) return; } catch { }
            try { SetProcessDPIAware(); } catch { }
        }

        public static Rectangle Cliente(IntPtr h)
        {
            RECT c;
            if (!GetClientRect(h, out c)) return Rectangle.Empty;
            POINT p = new POINT(0, 0);
            ClientToScreen(h, ref p);
            return new Rectangle(p.X, p.Y, c.R - c.L, c.B - c.T);
        }

        public static string Texto(IntPtr h) { StringBuilder s = new StringBuilder(256); GetWindowText(h, s, 256); return s.ToString(); }
        public static string Classe(IntPtr h) { StringBuilder s = new StringBuilder(256); GetClassName(h, s, 256); return s.ToString(); }
    }

    // Janela transparente por cima do jogo (desenho com transparencia por pixel).
    // "clicavel" = false: os cliques passam para o jogo (aviso). true: recebe o
    // clique e nao deixa passar (barreira). Nunca rouba o foco do jogo.
    public sealed class Camada : Form
    {
        readonly bool clicavel;
        public event EventHandler Clicada;

        public Camada(bool clicavel)
        {
            this.clicavel = clicavel;
            FormBorderStyle = FormBorderStyle.None;
            ShowInTaskbar = false;
            StartPosition = FormStartPosition.Manual;
            Text = "Treinador TCG";
            Bounds = new Rectangle(-32000, -32000, 1, 1);
        }

        protected override CreateParams CreateParams
        {
            get
            {
                CreateParams p = base.CreateParams;
                p.ExStyle |= Nativo.WS_EX_LAYERED | Nativo.WS_EX_TOOLWINDOW | Nativo.WS_EX_NOACTIVATE | Nativo.WS_EX_TOPMOST;
                if (!clicavel) p.ExStyle |= Nativo.WS_EX_TRANSPARENT;
                return p;
            }
        }

        protected override bool ShowWithoutActivation { get { return true; } }

        protected override void WndProc(ref Message m)
        {
            const int WM_MOUSEACTIVATE = 0x21, MA_NOACTIVATE = 3;
            if (m.Msg == WM_MOUSEACTIVATE) { m.Result = new IntPtr(MA_NOACTIVATE); return; }
            base.WndProc(ref m);
        }

        protected override void OnMouseUp(MouseEventArgs e)
        {
            base.OnMouseUp(e);
            if (clicavel && e.Button == MouseButtons.Left && Clicada != null) Clicada(this, EventArgs.Empty);
        }

        public void Mostrar(Bitmap imagem, Point onde)
        {
            IntPtr tela = Nativo.GetDC(IntPtr.Zero);
            IntPtr mem = Nativo.CreateCompatibleDC(tela);
            IntPtr hb = IntPtr.Zero, velho = IntPtr.Zero;
            try
            {
                hb = imagem.GetHbitmap(Color.FromArgb(0));
                velho = Nativo.SelectObject(mem, hb);
                Nativo.SIZE tam = new Nativo.SIZE(imagem.Width, imagem.Height);
                Nativo.POINT src = new Nativo.POINT(0, 0), dst = new Nativo.POINT(onde.X, onde.Y);
                Nativo.BLENDFUNCTION bl = new Nativo.BLENDFUNCTION();
                bl.Op = 0; bl.Flags = 0; bl.Alpha = 255; bl.Format = 1;
                Nativo.UpdateLayeredWindow(Handle, tela, ref dst, ref tam, mem, ref src, 0, ref bl, 2);
            }
            finally
            {
                Nativo.ReleaseDC(IntPtr.Zero, tela);
                if (hb != IntPtr.Zero) { Nativo.SelectObject(mem, velho); Nativo.DeleteObject(hb); }
                Nativo.DeleteDC(mem);
            }
            if (!Visible) Show();
            NaFrente();
        }

        public void NaFrente()
        {
            const uint NOSIZE = 0x1, NOMOVE = 0x2, NOACTIVATE = 0x10, SHOWWINDOW = 0x40;
            Nativo.SetWindowPos(Handle, new IntPtr(-1), 0, 0, 0, 0, NOSIZE | NOMOVE | NOACTIVATE | SHOWWINDOW);
        }

        public void Esconder() { if (Visible) Hide(); }
    }

    // ---- O vigia -------------------------------------------------------------
    public sealed class Vigia
    {
        readonly ApplicationContext contexto = new ApplicationContext();
        readonly System.Windows.Forms.Timer relogio = new System.Windows.Forms.Timer();
        readonly ConcurrentQueue<string> entrada = new ConcurrentQueue<string>();
        readonly Camada aviso = new Camada(false);
        readonly Camada barreira = new Camada(true);
        readonly int pai;
        readonly bool depurar;
        bool barreiraLigada;
        readonly string tituloJogo, classeJogo;

        IntPtr jogo = IntPtr.Zero;
        DateTime procurouJogo = DateTime.MinValue, conferiuPai = DateTime.MinValue;
        Bitmap foto;
        bool pelaTela, exclusaoAplicada;

        int estavel, cruBruto = -1, repeticoes;
        Deteccao ultima = new Deteccao();
        bool emSessao, registradoNaSessao, barreiraLiberada, tocouSom;
        DateTime inicioSessao, ultimoRegistrado = DateTime.MinValue, okAte = DateTime.MinValue;
        // A tela de resultado as vezes some por 1 a 3 s e volta (o detector
        // perde uma ou duas fotos). Se a anterior ja estava registrada e sumiu
        // ha menos de 60 s, e a mesma partida: o aviso nao volta (2.6.10;
        // nenhuma partida nova termina tao rapido).
        bool ultimaSessaoRegistrada;
        DateTime fimUltimaSessao = DateTime.MinValue;
        const double MESMA_TELA_S = 60;
        Rectangle ultimoCartao = Rectangle.Empty;
        string chaveAviso = "", chaveBarreira = "";

        public Vigia(int pai, bool barreira, bool depurar)
        {
            this.pai = pai;
            this.barreiraLigada = barreira;
            this.depurar = depurar;
            string t = Environment.GetEnvironmentVariable("TTCG_VIGIA_TITULO");
            string c = Environment.GetEnvironmentVariable("TTCG_VIGIA_CLASSE");
            tituloJogo = string.IsNullOrEmpty(t) ? "TCG Live" : t;
            classeJogo = string.IsNullOrEmpty(c) ? "UnityWndClass" : c;
            this.barreira.Clicada += delegate { LiberarBarreira(); };
        }

        public static int Rodar(string[] args)
        {
            int pai = 0; bool barreira = true, depurar = false, semEntrada = false;
            for (int i = 0; i < args.Length; i++)
            {
                string a = args[i].ToLowerInvariant();
                if (a == "-pai" && i + 1 < args.Length) int.TryParse(args[++i], out pai);
                else if (a == "-barreira" && i + 1 < args.Length) barreira = args[++i] != "0";
                else if (a == "-depurar") depurar = true;
                else if (a == "-sementrada") semEntrada = true;
            }
            // Quem inicia o vigia escondido (o painel) pede SW_HIDE no
            // STARTUPINFO, e o Windows aplica isso ao primeiro ShowWindow do
            // processo: gasta esse primeiro com uma janela que nunca aparece.
            using (Form gasto = new Form()) { Nativo.ShowWindow(gasto.Handle, 0); }
            Vigia v = new Vigia(pai, barreira, depurar);
            if (!semEntrada) v.LerEntrada();
            v.relogio.Interval = 1000;
            v.relogio.Tick += delegate { v.Tique(); };
            v.relogio.Start();
            v.Evento("pronto", "versao", "1");
            Application.Run(v.contexto);
            return 0;
        }

        void LerEntrada()
        {
            Thread t = new Thread(delegate ()
            {
                try
                {
                    string l;
                    while ((l = Console.In.ReadLine()) != null) entrada.Enqueue(l.Trim());
                }
                catch { }
                entrada.Enqueue("__fim");
            });
            t.IsBackground = true;
            t.Start();
        }

        // ---- Saida (JSON por linha) ----
        static string J(string s)
        {
            StringBuilder b = new StringBuilder("\"");
            foreach (char ch in s)
            {
                if (ch == '"' || ch == '\\') b.Append('\\').Append(ch);
                else if (ch < 32) b.Append("\\u").Append(((int)ch).ToString("x4"));
                else b.Append(ch);
            }
            return b.Append('"').ToString();
        }

        static string R(Rectangle r)
        {
            if (r.IsEmpty) return "null";
            return "[" + r.X + "," + r.Y + "," + r.Width + "," + r.Height + "]";
        }

        public void Evento(string nome, params object[] pares)
        {
            StringBuilder b = new StringBuilder("{\"evento\":").Append(J(nome));
            for (int i = 0; i + 1 < pares.Length; i += 2)
            {
                b.Append(',').Append(J(pares[i].ToString())).Append(':');
                object v = pares[i + 1];
                if (v == null) b.Append("null");
                else if (v is bool) b.Append((bool)v ? "true" : "false");
                else if (v is int || v is long || v is double) b.Append(Convert.ToString(v, CultureInfo.InvariantCulture));
                else if (v is Rectangle) b.Append(R((Rectangle)v));
                else b.Append(J(v.ToString()));
            }
            b.Append('}');
            try { Console.Out.WriteLine(b.ToString()); Console.Out.Flush(); } catch { }
        }

        void Sair()
        {
            relogio.Stop();
            try { aviso.Close(); barreira.Close(); } catch { }
            contexto.ExitThread();
        }

        // ---- Ciclo principal ----
        void Tique()
        {
            try { TiqueSeguro(); }
            catch (Exception e)
            {
                Evento("erro", "mensagem", e.GetType().Name + ": " + e.Message);
                EsconderTudo();
            }
        }

        void TiqueSeguro()
        {
            string msg;
            while (entrada.TryDequeue(out msg))
            {
                if (msg == "registrado") Registrado();
                else if (msg == "barreira 0") { barreiraLigada = false; chaveBarreira = ""; }
                else if (msg == "barreira 1") { barreiraLigada = true; chaveBarreira = ""; }
                else if (msg == "sair" || msg == "__fim") { Sair(); return; }
            }
            DateTime agora = DateTime.Now;
            if (pai > 0 && (agora - conferiuPai).TotalSeconds >= 5)
            {
                conferiuPai = agora;
                try { Process.GetProcessById(pai); } catch { Sair(); return; }
            }
            if (jogo == IntPtr.Zero || !Nativo.IsWindow(jogo) || !Nativo.IsWindowVisible(jogo))
            {
                jogo = IntPtr.Zero;
                if ((agora - procurouJogo).TotalSeconds < 3) { EsconderTudo(); return; }
                procurouJogo = agora;
                jogo = AcharJogo();
                if (jogo == IntPtr.Zero) { relogio.Interval = 2000; Aplicar(0, null, agora, false); return; }
                Evento("jogo", "titulo", Nativo.Texto(jogo), "classe", Nativo.Classe(jogo));
            }
            if (Nativo.IsIconic(jogo)) { EsconderTudo(); return; }
            Rectangle cli = Nativo.Cliente(jogo);
            if (cli.Width < 320 || cli.Height < 180) { EsconderTudo(); return; }
            IntPtr frente = Nativo.GetForegroundWindow();
            bool naFrente = frente == jogo || frente == aviso.Handle || frente == barreira.Handle;
            int[] px = Fotografar(cli, naFrente);
            if (px == null) { EsconderTudo(); return; }
            Deteccao d = Detector.Analisar(px, cli.Width, cli.Height);
            Aplicar(d.Tela, d, agora, naFrente);
            if (emSessao) Desenhar(cli, naFrente, agora);
            relogio.Interval = emSessao ? 500 : 1000;
        }

        IntPtr AcharJogo()
        {
            IntPtr achado = IntPtr.Zero;
            string titulo = tituloJogo, classe = classeJogo;
            Nativo.EnumWindows(delegate (IntPtr h, IntPtr l)
            {
                if (!Nativo.IsWindowVisible(h)) return true;
                string t = Nativo.Texto(h);
                if (t.IndexOf(titulo, StringComparison.OrdinalIgnoreCase) < 0) return true;
                if (classe != "*" && Nativo.Classe(h) != classe) return true;
                if (h == aviso.Handle || h == barreira.Handle) return true;
                achado = h;
                return false;
            }, IntPtr.Zero);
            return achado;
        }

        // Foto so da janela do jogo. PrintWindow (PW_CLIENTONLY |
        // PW_RENDERFULLCONTENT) nao ve os avisos por cima e funciona mesmo com
        // outra janela na frente. Se vier preta (algumas placas), usa a tela,
        // com os avisos excluidos da captura.
        int[] Fotografar(Rectangle cli, bool naFrente)
        {
            if (foto == null || foto.Width != cli.Width || foto.Height != cli.Height)
            {
                if (foto != null) foto.Dispose();
                foto = new Bitmap(cli.Width, cli.Height, PixelFormat.Format32bppArgb);
            }
            if (!pelaTela)
            {
                using (Graphics g = Graphics.FromImage(foto))
                {
                    IntPtr dc = g.GetHdc();
                    try { Nativo.PrintWindow(jogo, dc, 3); } finally { g.ReleaseHdc(dc); }
                }
                int[] px = Detector.Pixels(foto);
                if (!QuasePreta(px)) return px;
                pelaTela = true;
                Evento("captura", "modo", "tela");
            }
            if (!naFrente) return null;
            if (!exclusaoAplicada)
            {
                exclusaoAplicada = true;
                try { Nativo.SetWindowDisplayAffinity(aviso.Handle, 0x11); Nativo.SetWindowDisplayAffinity(barreira.Handle, 0x11); } catch { }
            }
            using (Graphics g = Graphics.FromImage(foto)) g.CopyFromScreen(cli.X, cli.Y, 0, 0, cli.Size);
            return Detector.Pixels(foto);
        }

        static bool QuasePreta(int[] px)
        {
            int claros = 0, n = 0;
            for (int i = 0; i < px.Length; i += 997) { n++; int c = px[i]; if (((c >> 16) & 255) + ((c >> 8) & 255) + (c & 255) > 30) claros++; }
            return n > 0 && claros < n * 0.02;
        }

        // Estabiliza (2 fotos seguidas para aparecer ou sumir; 1 <-> 2 na hora)
        // e controla a sessao (uma tela de resultado do comeco ao fim).
        void Aplicar(int cru, Deteccao d, DateTime agora, bool naFrente)
        {
            if (d != null && d.Tela > 0) ultima = d;
            if (cru == estavel) repeticoes = 0;
            else if (estavel != 0 && cru != 0) estavel = cru;
            else
            {
                if (cru == cruBruto) repeticoes++; else repeticoes = 1;
                if (repeticoes >= 2) { estavel = cru; repeticoes = 0; }
            }
            cruBruto = cru;
            if (estavel != 0 && !emSessao)
            {
                emSessao = true;
                inicioSessao = agora;
                registradoNaSessao = (agora - ultimoRegistrado).TotalSeconds < 45
                    || (ultimaSessaoRegistrada && (agora - fimUltimaSessao).TotalSeconds < MESMA_TELA_S);
                barreiraLiberada = false;
                tocouSom = false;
                ultimoCartao = Rectangle.Empty;
                Evento("sessao", "inicio", true, "registrada", registradoNaSessao);
            }
            else if (estavel == 0 && emSessao)
            {
                emSessao = false;
                double dur = (agora - inicioSessao).TotalSeconds;
                if (!registradoNaSessao && dur >= 1) Evento("sem_registro", "segundos", (int)dur, "barreiraLiberada", barreiraLiberada);
                Evento("sessao", "inicio", false, "registrada", registradoNaSessao, "segundos", (int)dur);
                ultimaSessaoRegistrada = registradoNaSessao;
                fimUltimaSessao = agora;
                EsconderTudo();
            }
            if (depurar && d != null) Evento("deteccao", "tela", d.Tela, "estavel", estavel, "motivo", d.Motivo, "botao", d.Botao, "continuar", d.Continuar, "exportar", d.Exportar, "painel", d.Painel);
        }

        void Registrado()
        {
            DateTime agora = DateTime.Now;
            ultimoRegistrado = agora;
            if (emSessao && !registradoNaSessao)
            {
                registradoNaSessao = true;
                okAte = agora.AddSeconds(2.5);
                Evento("registrada");
            }
        }

        void LiberarBarreira()
        {
            if (barreiraLiberada) return;
            barreiraLiberada = true;
            barreira.Esconder();
            chaveBarreira = "";
            Evento("barreira_liberada");
        }

        void EsconderTudo()
        {
            aviso.Esconder();
            barreira.Esconder();
            chaveAviso = "";
            chaveBarreira = "";
        }

        void Desenhar(Rectangle cli, bool naFrente, DateTime agora)
        {
            if (!naFrente) { EsconderTudo(); return; }
            int etapa;
            if (registradoNaSessao) etapa = agora < okAte ? 3 : 0;
            else etapa = estavel == 2 && !ultima.Exportar.IsEmpty ? 2 : 1;
            bool comBarreira = barreiraLigada && !barreiraLiberada && !registradoNaSessao;
            Plano p = Planejador.Planejar(ultima, cli.Size, etapa, ultimoCartao, comBarreira);
            if (etapa == 0) aviso.Esconder();
            else
            {
                string chave = p.Chave() + "|" + cli;
                if (chave != chaveAviso)
                {
                    using (Bitmap b = Desenho.Aviso(p, cli.Size)) aviso.Mostrar(b, cli.Location);
                    chaveAviso = chave;
                    if (etapa != 3) ultimoCartao = p.Cartao;
                    if (depurar) Evento("aviso", "etapa", etapa, "cartao", Desloca(p.Cartao, cli), "alvo", Desloca(p.Alvo, cli));
                    if (etapa == 1 && !tocouSom) { tocouSom = true; try { System.Media.SystemSounds.Asterisk.Play(); } catch { } }
                }
                else aviso.NaFrente();
            }
            if (p.Barreira.IsEmpty) barreira.Esconder();
            else
            {
                Rectangle onde = Desloca(p.Barreira, cli);
                string chave = onde.ToString();
                if (chave != chaveBarreira)
                {
                    using (Bitmap b = Desenho.Barreira(onde.Size, p.Escala)) barreira.Mostrar(b, onde.Location);
                    chaveBarreira = chave;
                    if (depurar) Evento("barreira", "area", onde);
                }
                else barreira.NaFrente();
            }
        }

        static Rectangle Desloca(Rectangle r, Rectangle cli)
        {
            if (r.IsEmpty) return r;
            return new Rectangle(r.X + cli.X, r.Y + cli.Y, r.Width, r.Height);
        }
    }
}
