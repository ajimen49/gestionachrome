# GestionaChrome

**Eina de gestió de perfils de Google Chrome per a Windows**

GestionaChrome és una utilitat gràfica per a Windows que permet exportar, importar i eliminar perfils de Google Chrome de forma senzilla, sense coneixements tècnics. Pensada especialment per facilitar el canvi d'ordinador sense perdre cap dada.

---

## Característiques

- Interfície gràfica clara i en català
- Exportació selectiva per perfil: tries exactament quines dades vols
- Importació amb previsualització: veus el contingut del ZIP abans d'importar res
- Merge segur: no sobreescriu res del Chrome de destinació que no hagis triat
- Eliminació de perfils amb confirmació
- Compatible amb múltiples perfils de Chrome al mateix ordinador
- Portable: no requereix instal·lació

### Dades que es poden exportar i importar

| Opció | Contingut |
|---|---|
| **Preferits** | Adreces d'interès i icones de lloc web |
| **Historial** | Historial de navegació, llocs més visitats i historial de la barra d'adreces |

> Les contrasenyes de Chrome estan xifrades per Windows i no es poden transferir entre ordinadors. Es poden recuperar automàticament iniciant sessió a Chrome amb el compte de Google.

---

## Requisits

- Windows 10 o Windows 11
- PowerShell 5.1 o superior (inclòs per defecte a Windows 10/11)
- Google Chrome instal·lat a la màquina d'origen

---

## Mètodes d'execució

### Mètode 1 — ZIP (recomanat)

És el mètode més compatible amb entorns corporatius i educatius, ja que no genera alertes d'antivirus.

1. Descarrega el fitxer `GestionaChrome_v2.5.zip` de la secció [Releases](../../releases/latest)
2. Extreu el contingut en qualsevol carpeta (per exemple, l'Escriptori)
3. Fes doble clic a **`GestionaChrome_v2.5.bat`**
4. Si Windows mostra un avís de seguretat, fes clic a "Més informació" → "Executa igualment"

> El fitxer `.bat` obre PowerShell en mode bypass automàticament. No cal canviar cap configuració del sistema.

### Mètode 2 — EXE

Més còmode d'executar però pot ser bloquejat per alguns antivirus corporatius (Windows Defender, CrowdStrike, etc.).

1. Descarrega el fitxer `GestionaChrome_v2.5.exe` de la secció [Releases](../../releases/latest)
2. Fes doble clic per executar-lo
3. Si l'antivirus el bloqueja, utilitza el Mètode 1

> L'executable és l'script PowerShell compilat amb PS2EXE. El codi font és públic i auditable en aquest repositori.

---

## Guia d'ús

### Exportar (ordinador antic)

1. Executa GestionaChrome a l'**ordinador antic**
2. Selecciona **EXPORTAR**
3. Es mostrarà una taula amb tots els perfils de Chrome detectats
4. Marca les columnes que vols exportar per a cada perfil
5. Fes clic a **EXPORTAR** i tria on desar el fitxer ZIP
6. Copia el fitxer ZIP a l'ordinador nou (per USB, xarxa, núvol, etc.)

### Importar (ordinador nou)

1. Executa GestionaChrome a l'**ordinador nou**
2. Selecciona **IMPORTAR**
3. Selecciona el fitxer ZIP generat al pas anterior
4. Es mostrarà una taula amb els perfils continguts al ZIP
5. Tria quins perfils i quines dades vols importar
6. Fes clic a **IMPORTAR**
7. Obre Google Chrome: els perfils i les dades estaran disponibles

> Els avatars dels perfils vinculats a un compte de Google es recuperen automàticament quan l'usuari inicia sessió a Chrome.

### Eliminar perfils

1. Executa GestionaChrome
2. Selecciona **ELIMINAR**
3. Marca els perfils que vols eliminar
4. Confirma l'operació

> Aquesta acció elimina la carpeta del perfil i la seva entrada al registre intern de Chrome. No es pot desfer.

---

## Preguntes freqüents

**Cal tancar Chrome abans d'usar l'eina?**
Sí. GestionaChrome ho detecta automàticament i ofereix tancar-lo.

**Puc importar en un Chrome que ja té perfils configurats?**
Sí. L'eina fa un merge selectiu: afegeix els perfils nous sense modificar els que ja existeixen.

**Funcionarà si l'ordinador nou té una versió diferent de Chrome?**
Sí, sempre que sigui una versió igual o superior a la de l'ordinador antic.

**El fitxer `.ps1` mostra un avís de seguretat en fer doble clic.**
És normal quan el fitxer s'ha descarregat d'Internet. Solució: clic dret → Propietats → marcar "Desbloqueja" → Acceptar. O bé usar sempre el `.bat` inclòs al ZIP, que no requereix aquest pas.

**Per què no s'inclouen les contrasenyes?**
Les contrasenyes de Chrome estan xifrades per Windows amb DPAPI, un sistema lligat al compte i la màquina concreta. Copiar-les a un altre ordinador fa que Chrome no les pugui desxifrar. La manera correcta de recuperar-les és iniciar sessió a Chrome amb el compte de Google, que les sincronitza automàticament.

---

## Llicència

MIT — lliure per usar, modificar i distribuir, fins i tot en entorns corporatius o educatius.

---

## Crèdits

Desenvolupat per [@ajimen49](https://github.com/ajimen49).

Suggeriments i millores benvinguts via [Issues](../../issues).
