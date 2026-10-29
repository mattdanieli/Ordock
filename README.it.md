<p align="center">
  <img src="docs/icon.png" width="128" alt="Icona di Ordock">
</p>

<h1 align="center">Ordock</h1>
<p align="center"><b>Metti in ordine il Dock del Mac, con un clic.</b><br>
Ordina le app del Dock per nome, colore, ultimo utilizzo o categoria, dalla barra dei menu.</p>

<p align="center">
  <a href="../../releases/latest/download/Ordock.zip"><img alt="Scarica per macOS" src="https://img.shields.io/badge/Scarica-macOS-111111?style=for-the-badge&logo=apple&logoColor=white"></a>
</p>
<p align="center"><sub>Gratis · Open source · macOS 13 Ventura o successivo (Apple Silicon e Intel) · Italiano e English · <a href="../../releases">Tutte le versioni</a></sub></p>

<p align="center">
  <a href="README.md">🇬🇧 English</a> · <a href="README.it.md">🇮🇹 Italiano</a>
</p>

<p align="center">
  <img src="docs/examples.png" alt="Esempi: il Dock prima, ordinato per colore e ordinato per categoria" width="900">
</p>

---

## Il problema

Le app si accumulano nel Dock nell'ordine in cui le hai aggiunte. Dopo un po', per trovare l'icona giusta
devi scorrere tutta la fila ogni volta, e spostare le icone una a una per riordinarle è noioso.

## La soluzione

Ordock vive nella barra dei menu e riordina le app del Dock al posto tuo: in ordine alfabetico, come un
arcobaleno, in base a quando le hai usate o raggruppate per tipo. Se il risultato non ti piace, un clic
e torna tutto com'era.

## Funzioni

- **Ordina per nome:** dalla A alla Z, con un clic
- **Ordina per colore:** analizza ogni icona e le mette in fila come un arcobaleno (rossi → arancioni →
  gialli → verdi → blu → viola), con le icone grigie, bianche e nere in fondo
- **Ordina per ultimo utilizzo:** le app usate più di recente vanno per prime, a **sinistra** o a
  **destra** del Dock, come preferisci
- **Ordina per categoria:** raggruppa le app (Browsing, Mail, Socials, Grafica, Video, Musica e audio,
  Lavoro, Sviluppo, Utility, Svago, Sistema, Altro) con un piccolo spazio tra un gruppo e l'altro
  - clicca una categoria per metterla **per prima**, a sinistra nel Dock: gli altri gruppi seguono
  - le app più comuni vengono riconosciute da sole; puoi spostare qualsiasi app e creare gruppi tuoi
  - gruppi in ordine **alfabetico**, oppure trascinali nell'ordine che vuoi
- **Ordini salvati:** salva il Dock come "Lavoro" o "Weekend" e richiamalo con un clic
- **Pulizia del Dock:** trova le app che non apri da 1, 3, 6 o 12 mesi (e quelle cancellate dal Mac)
  e ti fa scegliere quali togliere dal Dock
- **Scorciatoia da tastiera:** **⌃⌥⌘ O** ripete l'ultimo ordinamento, da qualsiasi app (oppure ⌃⌥⌘ D / R, o nessuna)
- **Finestra impostazioni** con tutte le opzioni in un unico posto
- **Italiano e inglese:** scegli la lingua durante l'installazione e cambiala quando vuoi dal menu
- **Sicura:**
  - la prima volta che ordini, l'ordine originale viene salvato e **Ripristina** lo rimette
  - se non riesce a salvare la copia di sicurezza, il Dock non viene toccato
  - il ripristino non toglie mai le app aggiunte dopo: finiscono in fondo
  - la pulizia salva prima l'ordine attuale, così puoi tornare indietro da **Ordini salvati**
  - le app non vengono mai cancellate dal Mac: spariscono solo dal Dock
- **Nativa e leggera:** scritta in Swift, senza internet, senza account, nessun dato raccolto

## Scarica e installa

1. Scarica **[Ordock.zip](../../releases/latest/download/Ordock.zip)** e fai doppio clic per estrarlo.
2. Trascina **Ordock.app** nella cartella **Applicazioni**.
3. La prima volta fai **clic destro su Ordock.app → Apri** e conferma.
   Sulle versioni recenti di macOS può servire **Impostazioni di Sistema → Privacy e sicurezza → Apri comunque**.
4. Cerca l'**icona del Dock nella barra dei menu**, in alto a destra vicino all'orologio.

> **Perché compare l'avviso?** Ordock non è notarizzata da Apple (serve un account sviluppatore a pagamento),
> quindi macOS chiede conferma la prima volta. Tutto il codice sorgente è qui, in questo repository.

## Inizia subito

1. Clicca l'icona di Ordock nella barra dei menu.
2. Scegli **Ordina per nome**, **Ordina per colore**, **Ordina per ultimo utilizzo** oppure **Ordina per categoria**.
3. Il Dock sparisce e riappare per un secondo (è così che macOS lo ricarica) e le app sono in ordine.
4. Hai cambiato idea? **Ripristina ordine originale**.

## Guida

### Il menu

| Voce del menu | Cosa fa |
|---|---|
| **Ordina per nome (A → Z)** | Ordine alfabetico |
| **Ordina per colore** | Ordine arcobaleno, icone neutre in fondo |
| **Ordina per ultimo utilizzo ›** | *Più recenti a sinistra* oppure *Più recenti a destra* |
| **Ordina per categoria › Metti per prima nel Dock** | Clicchi una categoria: le sue app vanno per prime, gli altri gruppi seguono |
| **Ordina per categoria › Tutte in ordine, nessuna per prima** | Tutti i gruppi nel loro ordine, senza preferenze |
| **Ordina per categoria › Cambia categoria a un'app** | Scegli l'app, poi il nuovo gruppo |
| **Ordini salvati ›** | Applica, salva o elimina una disposizione del Dock |
| **Pulizia Dock ›** | Trova le app non usate da 1, 3, 6 o 12 mesi |
| **Ripristina ordine originale** | Rimette il Dock com'era prima del primo ordinamento |
| **Salva l'ordine attuale come originale…** | Il Dock di oggi diventa il nuovo "originale" |
| **Impostazioni… (⌘ ,)** | Apre la finestra delle impostazioni |
| **Lingua ›** | Automatica, Italiano o English |
| **Scorciatoia ›** | ⌃⌥⌘ O, D o R, oppure nessuna |

### La finestra impostazioni

- **Generale:** lingua, apri all'avvio, scorciatoia da tastiera
- **Ordina:** un pulsante per ogni tipo di ordinamento
- **Categorie:** a sinistra i tuoi gruppi con quante app contengono (trascinali per riordinarli, **+** / **−**
  per aggiungere o togliere i tuoi); a destra le app del gruppo selezionato, con **Sposta in** e
  **Aggiungi app a questo gruppo**. Scegli l'ordine dei gruppi **Alfabetico** o **Personalizzato**
  e se lasciare gli spazi tra i gruppi
- **Ordini salvati:** salva, applica ed elimina le tue disposizioni
- **Pulizia e ripristino:** pulizia del Dock, ripristino dell'originale, cartella delle copie di sicurezza

### Come funziona "ultimo utilizzo"

Ordock unisce due fonti: la data che macOS registra ogni volta che apri un'app, e un suo registro di ogni
volta che passi a un'app mentre Ordock è aperta. Più a lungo resta aperta, più l'ordine è preciso.
Le app mai aperte vanno in fondo.

## Esempi

**"Cerco sempre prima le app di grafica."**
Ordina per categoria › Metti per prima: **Grafica**. Photoshop, Illustrator, Figma… stanno a sinistra
nel Dock, poi Browsing, Mail, Musica e il resto, ogni gruppo separato da un piccolo spazio.

**"Voglio vicino al Finder le app che sto usando adesso."**
Ordina per ultimo utilizzo › **Più recenti a sinistra**. Premi **⌃⌥⌘ O** quando vuoi aggiornarlo.

**"Il Dock deve rispecchiare il mio umore."**
Ordina per colore per un Dock arcobaleno. Salvalo come **"Arcobaleno"** in Ordini salvati, poi torna alla
disposizione **"Lavoro"** con un clic.

**"Il mio Dock è pieno di app che non apro mai."**
Pulizia Dock › **6 mesi**. Spunta le app che non ti servono e clicca **Togli dal Dock**.
La disposizione di prima viene salvata come *"Prima della pulizia"*, per sicurezza.

**"Ho aggiunto un'app di lavoro ed è finita in Altro."**
Ordina per categoria › Cambia categoria a un'app › scegli l'app › **Lavoro**. Ordock se lo ricorda.

## Domande frequenti

**Ordock cancella le app?** No. Cambia solo l'ordine delle icone nel Dock. La pulizia toglie le icone
dal Dock, mai le app dal Mac.

**Cosa viene ordinato?** Le app fisse nella parte sinistra del Dock. Cartelle, Download, Cestino e app
recenti restano dove sono.

**L'ordine per colore mette tutto insieme?** Con gli stili icone *Colorato* o *Trasparente* di
Impostazioni di Sistema → Aspetto le icone hanno tutte lo stesso colore: usa lo stile *Predefinito*.

**Dove sono le copie di sicurezza?** In `~/Library/Application Support/Ordock/`
(Impostazioni → Pulizia e ripristino → *Apri la cartella delle copie di sicurezza*).

**Prima usavo "Riordina Dock".** Era il vecchio nome di Ordock. L'installazione toglie la vecchia app e
Ordock recupera da sola le sue copie di sicurezza.

## Compilare dal codice

Serve **Xcode** (o gli strumenti da riga di comando) e macOS 13 o successivo.

1. Scarica questo repository (**Code → Download ZIP**) ed estrailo.
2. Apri **Terminale**, scrivi `bash ` (con uno spazio), trascina dentro **Install Ordock.command** e premi **Invio**.
3. Scegli la lingua: l'app viene compilata, copiata in Applicazioni e aperta.

Ogni modifica su `main` compila l'app in automatico (scheda **Actions**) e ogni nuova versione viene
pubblicata in **[Releases](../../releases)** con `Ordock.zip` allegato.

## Supporta

Ordock è gratis. Se ti rende la giornata un po' più ordinata, puoi offrirmi un caffè:
**[paypal.me/mattdanieli](https://paypal.me/mattdanieli)** ❤️

Altre app: **[mattdanieli.it/apps](https://www.mattdanieli.it/apps/)**

## Licenza

[MIT](LICENSE)

<p align="center"><sub>Made With Love ❤️ by MattDanieli</sub></p>
