Při fyzikální simulaci zdi v mřížkovém modelu (gridu) musíš pracovat se dvěma hlavními vlastnostmi: **tepelným odporem (izolací)** a **tepelnou kapacitou (akumulací)**.

V mřížce to znamená, že buňka typu "zeď" se chová jako "brzda" pro teplo tekoucí skrz ni a zároveň jako "houba", která teplo nasákne a drží ho v sobě.

Zde je návod, jak to implementovat v rámci tvého `SimulationEngine`:

---

### 1. Tepelná vodivost (Přenos)

Místo jedné globální rychlosti šíření tepla musíš pro každou buňku (nebo rozhraní mezi buňkami) definovat koeficient prostupu.

V diskrétním modelu to vyřešíš úpravou vzorce pro změnu teploty . Pro buňku počítáš příspěvky od sousedů:

Kde \*\*\*\* je koeficient, který závisí na materiálu:

- **Vzduch-Vzduch:** Vysoké (teplo proudí volně).
- **Vzduch-Zeď:** Nízké (zeď klade odpor, teplo do ní vstupuje pomalu).
- **Zeď-Vzduch:** Nízké (teplo ze zdi uniká pomalu zpět do místnosti).

### 2. Akumulace (Kapacita)

Tady přichází ten rozdíl mezi "prázdným prostorem" a "hmotou". Zeď má mnohem vyšší **tepelnou setrvačnost**.

V kódu to simuluješ tak, že změna teploty v buňce zdi je "tlumena" její hmotou. Pokud do buňky vzduchu přiteče určité množství energie, její teplota vyskočí o 5 °C. Pokud stejné množství přiteče do zdi, její teplota se zvedne jen o 0.1 °C.

**Praktická implementace v simulaci:**
Zavedeš koeficient ** (setrvačnost)** pro každý typ materiálu:

- **Vzduch:** Malá kapacita ohřeje se hned.
- **Cihlová zeď:** Velká kapacita trvá jí hodiny reálného času (nebo tisíce kroků simulace), než se prohřeje skrz naskrz.

---

### 3. Jak to naprogramovat (Algoritmus)

Pro každou buňku v cyklu udělej toto:

1. **Vypočítej tok energie:** Zjisti rozdíl teplot mezi aktuální buňkou a jejími 4 sousedy.
2. **Aplikuj odpor:** Tento rozdíl vynásob koeficientem vodivosti rozhraní (např. pokud je jeden ze sousedů zeď, použij velmi malý násobič).
3. **Aplikuj akumulaci:** Výslednou změnu teploty vyděl "tepelnou kapacitou" aktuální buňky.

- _Výsledek:_ Zeď se bude ohřívat pomalu, ale jakmile bude horká, bude hřát i poté, co vypneš radiátor (přesně jako v realitě).

### 4. Co to znamená pro tvůj model `Cell`?

Tvé buňky by měly mít tyto fyzikální vlastnosti (uložené v `MaterialType`):

| Materiál    | Vodivost () | Kapacita () | Chování v simulaci                 |
| ----------- | ----------- | ----------- | ---------------------------------- |
| **Vzduch**  | 0.8         | 1           | Rychle vede, neudrží teplo.        |
| **Cihla**   | 0.1         | 50          | Špatně vede, obrovská setrvačnost. |
| **Izolace** | 0.01        | 5           | Skoro nevede, malá setrvačnost.    |

---

### Proč je to důležité pro tvůj projekt?

Díky tomuto modelu bude tvůj graf spotřeby vypadat realisticky:

1. **Start:** Zapneš topení, spotřeba je obrovská, protože ohříváš ledový vzduch i studené zdi.
2. **Provoz:** Jakmile se zdi "nabijí" teplem (akumulace), spotřeba klesne, protože termostat jen lehce přitápí a zdi mu pomáhají držet teplotu.
3. **Větrání:** Pokud bys přidal funkci otevření okna (změna zdi na vzduch), uvidíš, jak teplota v místnosti klesne, ale po zavření se díky teplým zdem rychle vrátí zpět (bez velkého topení).

**Chceš, abych ti definoval přesné koeficienty pro tyto materiály, které můžeš rovnou vložit do Dart kódu?** (Tím bys měl fyziku "zkalibrovanou" tak, aby se to chovalo uvěřitelně.)
