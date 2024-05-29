--baza se sastoji od 6 relacija: instruktori, polaznici, ispiti_teorija, ispiti_prva_pomoc, ispiti_voznja, voznje.

--objasnjavat cu dio po dio teksta zadatka:

----------------------------------------------------------------------------------------------
/*
Baza podataka čiju shemu gradite treba pokriti potrebe auto-škole. Auto-škola ima više
instruktor(ic)a, svatko ima jedan automobil. Također ima i više polaznika/polaznica koji ju upisuju i
plaćaju u jednoj ili više rata.
*/

create table instruktori (id_ins smallint not null, id_auto smallint not null, ime varchar, prezime varchar);
alter table instruktori
	add constraint pk_instruktor primary key (id_ins);
alter table instruktori
	add constraint jedan_auto unique (id_auto);


create table polaznici (id_pol smallint not null, ime varchar, prezime varchar,
platiti_uk int, placeno int, preostalo_sati int, teorija_p bool, prva_pomoc_p bool, voznja_p bool);
alter table polaznici
	add constraint pk_polaznik primary key (id_pol);
----------------------------------------------------------------------------------------------
/*
Uz svakog polaznika treba evidentirati ukupnu školarinu koju treba
platiti te ukupni do sada uplaćeni iznos, koji ne može biti veći od ukupne školarine, ali također prva
uplata mora biti najmanje trećina ukupne školarine. Nije potrebno evidentirati pojedinačne uplate,
nego samo kumulativno uplaćeni iznos. Ukupni iznos za platiti se može mijenjati tijekom vremena.
*/
alter table polaznici
	add constraint nije_placeno_previse check (platiti_uk >= placeno);
--ovdje se provjerava da nije placeno vise od ukupno potrebnog iznosa
alter table polaznici
	add constraint prva_rata check (3 * placeno >= platiti_uk);
--provjera da je prva uplata barem trecina ukupne, pretpostavka je da se vec pri registraciji treba
--uplatiti prva rata

--mogla bi jos postojati tablica sa popisom autiju, gdje bi primarni kljuc bio id_auto i jedan stupac
--za opis o kojem je autu rijec, ali za potrebu ove vjezbe nije nuzno

--testirajmo placanje:
insert into polaznici values (1,'franjo','drenski',100,40,35,false,false,false);
insert into polaznici values (2,'stef','guru',100,30,35,false,false,false);
insert into polaznici values (3,'jorge','jorge',100,35,35,false,false,false);
--ERROR:  new row for relation "polaznici" violates check constraint "prva_rata"
update polaznici
set placeno = placeno + 100
where id_pol = 1;
--ERROR:  new row for relation "polaznici" violates check constraint "nije_placeno_previse"
--na isti nacin se uplacuju rate:
update polaznici
set placeno = placeno + 20
where id_pol = 1;


----------------------------------------------------------------------------------------------
/*
Baza podataka treba omogućiti evidenciju ispita (teorija, prva pomoć, vožnja). Ispit je moguće
položiti ili ne. Nije moguće evidentirati ispit iz vožnje ako polaznik nema položene ispite iz teorije i
prve pomoći.
*/
--za ovaj dio koriste se teorija_p, prva_pomoc_p i voznja_p koji su tip bool i za svakog polaznika
--oznacavaju je li polozio ispite iz pojedinog predmeta

--takoder za svaki od predmeta postoji zasebna relacija u kojoj su evidentirani pojedini ispiti

create table ispiti_teorija (id_pol smallint not null, termin timestamp, prolaz bool);
alter table ispiti_teorija
	add constraint fk_teorija foreign key (id_pol) references polaznici;

create table ispiti_prva_pomoc (id_pol smallint not null, termin timestamp, prolaz bool);
alter table ispiti_prva_pomoc
	add constraint fk_prva_pomoc foreign key (id_pol) references polaznici;

create table ispiti_voznja (id_pol smallint not null, termin timestamp, prolaz bool);
alter table ispiti_voznja
	add constraint fk_voznja foreign key (id_pol) references polaznici;

--prilikom unosenja novog ispita u pojedinu tablicu (ovdje je primjer teorije) provjerava se je li
--postignut prolaz i ako je, teorija_p unutar relacije polaznici se pomocu triggera postavlja na true
--za tog polaznika
create or replace function teorija_prolaz()
returns trigger as $$
begin
    if new.prolaz = true and exists (select 1 from polaznici where id_pol = new.id_pol) then
        update polaznici
        set teorija_p = true
        where id_pol = new.id_pol;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger teorija_trigger
after insert on ispiti_teorija
for each row
execute function teorija_prolaz();

--ekvivalentno za prvu pomoc i voznju:
create or replace function prva_pomoc_prolaz()
returns trigger as $$
begin
    if new.prolaz = true and exists (select 1 from polaznici where id_pol = new.id_pol) then
        update polaznici
        set prva_pomoc_p = true
        where id_pol = new.id_pol;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger prva_pomoc_trigger
after insert on ispiti_prva_pomoc
for each row
execute function prva_pomoc_prolaz();

create or replace function voznja_prolaz()
returns trigger as $$
begin
    if new.prolaz = true and exists (select 1 from polaznici where id_pol = new.id_pol) then
        update polaznici
        set voznja_p = true
        where id_pol = new.id_pol;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger voznja_trigger
after insert on ispiti_voznja
for each row
execute function voznja_prolaz();

--primjer za unosenje prolaza iz teorije:
select ime, prezime, teorija_p from polaznici where id_pol = 1;
/*
  ime   | prezime | teorija_p 
--------+---------+-----------
 franjo | drenski | f
*/
insert into ispiti_teorija values (1,'1999-01-08 04:05:06',true);
select ime, prezime, teorija_p from polaznici where id_pol = 1;
/*
  ime   | prezime | teorija_p 
--------+---------+-----------
 franjo | drenski | t            --teorija_p je sad true

*/


--trigger evidencija_voznja_trigger sprjecava unosenje u tablicu ispiti_voznja ako nisu polozeni teorija
--i prva pomoc, takoder provjerava je li preostalo_sati za tog korisnika jednak nuli (to je kasniji
--dio ali sada je zgodnije objasniti taj dio koda)
create or replace function evidencija_voznja()
returns trigger as $$
begin
    if not exists (select 1 from polaznici where id_pol = new.id_pol 
    and teorija_p = true and prva_pomoc_p = true and preostalo_sati = 0) then
        raise exception 'nisu zadovoljeni uvjeti za polaganje voznje';
    end if;
    return new;
end;
$$ language plpgsql;

create trigger evidencija_voznja_trigger
before insert on ispiti_voznja
for each row
execute function evidencija_voznja();

--test:
insert into ispiti_voznja values (1,'1999-01-08 04:05:06',true);
--ERROR:  nisu zadovoljeni uvjeti za polaganje voznje
--u ovom slucaju nije polazena prva pomoc (i preostalo_sati je jos uvijek na 35).

--jos je moguce uvoditi ogranicenja na stupce teorija_p itd. iz tablice polaznici ali nije zapravo
--potrebno jer se je prijasnjim triggerima vec onemoguceno da npr. teorija ne bude polozena a voznja bude
--alter table polaznici add constraint ispit1 check (voznja_p = false or teorija_p = true);
--alter table polaznici add constraint ispit2 check (voznja_p = false or prva_pomoc_p = true);

----------------------------------------------------------------------------------------------
/*
Baza podataka treba omogućiti i evidenciju sati vožnje (polaznik, instruktor, datum, vrijeme). Izlazak
na ispit iz vožnje nije moguć ako polaznik nema najmanje 35 sati vožnje. U slučaju pada iz vožnje, uz
ispit se treba evidentirati i broj dodatnih sati vožnje koje polaznik treba odraditi prije sljedećeg
izlaska na ispit.
*/

--za ovaj dio koristi se relacija voznje koja sadrzi id polaznika, instruktora, vrijeme kada je voznja
--odrzana i broj sati odraden u tom terminu
create table voznje (id_pol smallint not null, id_ins smallint not null, termin timestamp, broj_sati int);
alter table voznje
	add constraint fk_pol foreign key (id_pol) references polaznici;
alter table voznje
	add constraint fk_ins foreign key (id_ins) references instruktori;

--dio sa izlaskom nakon najmanje 35 sati voznje vec je prije djelomicno prokomentiran, dakle provjerava
--se da je preostalo_sati na nuli. Pri unosenju u tablicu voznje, tom se polazniku preostalo_sati smanjuje
--za broj sati koji je odradio

create or replace function broj_sati()
returns trigger as $$
begin
        update polaznici
        set preostalo_sati = greatest(0, preostalo_sati - new.broj_sati) --ne ide u negativne vrijednosti
        where id_pol = new.id_pol;
    return new;
end;
$$ language plpgsql;

create trigger broj_sati_trigger
after insert on voznje
for each row
execute function broj_sati();

--primjer za ovu funkcionalnost:
--prvo treba upisati nekoliko instruktora:
insert into instruktori values (4,3,'john','smith');
insert into instruktori values (1,5,'bruno','mappa');
insert into instruktori values (2,1,'veljan','dragi');
insert into instruktori values (3,7,'ethan','legendica');

select ime, prezime, preostalo_sati from polaznici where id_pol = 2;
/*
 ime  | prezime | preostalo_sati 
------+---------+----------------
 stef | guru    |             35
 */
insert into voznje values (2,1,'1999-01-08 04:05:06',6);
select ime, prezime, preostalo_sati from polaznici where id_pol = 2;
/*
 ime  | prezime | preostalo_sati 
------+---------+----------------       -> broj sati smanjio se za 6
 stef | guru    |             29

*/

--dodajemo jos potrebne promjene za testiranje
insert into voznje values (2,2,'1999-01-08 04:05:06',10);
insert into voznje values (2,3,'1999-01-08 04:05:06',9);
insert into voznje values (2,1,'1999-01-08 04:05:06',7);
insert into voznje values (2,4,'1999-01-08 04:05:06',3);
insert into ispiti_teorija values (2,'1999-01-08 04:05:06',true);
insert into ispiti_prva_pomoc values (2,'1999-01-08 04:05:06',true);


--u slucaju da je ispit iz voznje evidentiran ali se dogodio pad, polazniku se preostalo_sati postavlja
--na 3, pa on moze opet pristupiti ispitu tek nakon sto odradi ta 3 sata voznje
create or replace function voznja_pad()
returns trigger as $$
begin
    if new.prolaz = false then
        update polaznici
        set preostalo_sati = 3
        where id_pol = new.id_pol;
    end if;
    return new;
end;
$$ language plpgsql;

create trigger voznja_pad_trigger
after insert on ispiti_voznja
for each row
execute function voznja_pad();

--primjer:
select ime, prezime, preostalo_sati from polaznici where id_pol = 2;
/* 
 ime  | prezime | preostalo_sati 
------+---------+----------------
 stef | guru    |              0
*/
insert into ispiti_voznja values (2,'1999-01-08 04:05:06',false);   --pad voznje
select ime, prezime, preostalo_sati from polaznici where id_pol = 2;
/*
ime  | prezime | preostalo_sati 
------+---------+----------------     -> broj potrebnih sati je sada 3
 stef | guru    |              3
*/

----------------------------------------------------------------------------------------------

/*
Baza podataka treba sadržavati pogled koji se koristi kao izvještaj o aktualnom stanju polaznika
(onih koji još uvijek nisu položili vožnju), a koji treba obuhvatiti financijsko stanje (uplaćeno / treba
još uplatiti), informaciju je li položio teoriju, je li položio prvu pomoć, koliko sati je vozio, koliko je puta izlazio na ispit iz vožnje te koliko dodatnih sati vožnje je ukupno imao određeno.
*/

--prvo se zbog preglednosti stvara view view1 koji sadrzi sve trazene podatke osim zadnja dva
create or replace view view1 as
select polaznici.id_pol, ime, prezime, platiti_uk - placeno as za_platiti,
	teorija_p as teorija_polozena, prva_pomoc_p as prva_pomoc_polozena,
	coalesce(sum(broj_sati),0) as odvozeno
from polaznici left join voznje on
	polaznici.id_pol = voznje.id_pol
where voznja_p = false
group by (polaznici.id_pol);

--u view2 nalazi se broj izlazaka na voznju. Dovoljno se samo prebrojiti sve izlaske za tog polaznika
--jer nas zanimaju samo oni koji nisu polozili voznju, pa su svi izlasci bili padovi
create or replace view view2 as
select id_pol, count(*) as izlasci_voznja
from ispiti_voznja
group by id_pol;

--konacno, stvara se view izvjestaj koji objedinjuje view1 i view2. Koristen je left join jer zelimo
--vidjeti podatke za sve korisnike cak i one koji nisu jos izasli na ispit iz voznje
create or replace view izvjestaj as
select view1.*, coalesce(izlasci_voznja,0) as izlasci_voznja,
	coalesce(izlasci_voznja*3,0) as dodatni_sati    --svaki izlazak je pad, pa je broj dodatnih sati samo broj izlazaka * 3
from view1 left join view2 on
	view1.id_pol = view2.id_pol;

--primjer: (siroko je, nadam se da ce se dobro vidjeti)
select * from izvjestaj;
 id_pol |  ime   | prezime | za_platiti | teorija_polozena | prva_pomoc_polozena | odvozeno | izlasci_voznja | dodatni_sati 
--------+--------+---------+------------+------------------+---------------------+----------+----------------+--------------
      2 | stef   | guru    |         60 | t                | t                   |       35 |              1 |            3
      1 | franjo | drenski |         40 | t                | t                   |        0 |              0 |            0
      3 | jorge  | jorge   |         65 | f                | f                   |        0 |              0 |            0


----------------------------------------------------------------------------------------------
/*
Baza podataka također treba sadržavati funkciju koja će vratiti poredak instruktora prema održanim
satima prema ulaznom parametru (godina za koju se poredak promatra). Uz ime i prezime
instruktora treba ispisati ukupan broj održanih sati u godini, te razliku u odnosu na prosječan broj
sati koji su svi instruktori te godine ostvarili.
*/

--prvo se definiraju dvije pomocne funkcije. Funkcija suma zbraja ukupan broj sati instruktuiranih u
--zadanoj godini, a broj_ljudi vraca broj aktivnih instruktora u toj godini

create or replace function suma(vrijeme int)
returns int as $$
declare
    value int;
begin
    select sum(broj_sati) into value from voznje where extract(year from termin) = vrijeme;
    return value;
end;
$$ language plpgsql;

create or replace function broj_ljudi(vrijeme int)
returns int as $$
declare
    value int;
begin
    select count(distinct id_ins) into value from voznje where extract(year from termin) = vrijeme;
    return value;
end;
$$ language plpgsql;


--zatim se stvara trazena funkcija koja vraca sve trazene podatke. Prosjek je dakako vrijednost od suma
--podijeljeno vrijednoscu od broj_ljudi za zadanu godinu. Nazalost mi funkcija ne vraca tablicu nego
--vektore vrijednosti za pojedinog instruktora

create or replace function instruk(godina int)
returns table (ime2 varchar, prezime2 varchar, broj bigint, razlika float) as $$
begin
    return query
    select ime as ime2, prezime as prezime2, sum(broj_sati) as broj,
    	sum(broj_sati) - cast(suma(godina) as float)/broj_ljudi(godina) as razlika
    from instruktori left join voznje on
    	instruktori.id_ins = voznje.id_ins
    where extract(year from termin) = godina
    group by instruktori.id_ins
    order by broj desc;
    return;
end;
$$ language plpgsql;

--primjer:
--dodajemo samo jos velik broj sati voznje ali u drugoj godini
insert into voznje values (3,4,'2000-01-08 04:05:06',100);

select * from voznje;
/*
 id_pol | id_ins |       termin        | broj_sati 
--------+--------+---------------------+-----------
      2 |      1 | 1999-01-08 04:05:06 |         6
      2 |      2 | 1999-01-08 04:05:06 |        10
      2 |      3 | 1999-01-08 04:05:06 |         9
      2 |      1 | 1999-01-08 04:05:06 |         7
      2 |      4 | 1999-01-08 04:05:06 |         3
      3 |      4 | 2000-01-08 04:05:06 |       100
*/
select * from instruktori;
/*
 id_ins | id_auto |  ime   |  prezime  
--------+---------+--------+-----------
      4 |       3 | john   | smith
      1 |       5 | bruno  | mappa
      2 |       1 | veljan | dragi
      3 |       7 | ethan  | legendica
*/

select instruk(1999);
/*
         instruk          
--------------------------
 (bruno,mappa,13,4.25)
 (veljan,dragi,10,1.25)
 (ethan,legendica,9,0.25)
 (john,smith,3,-5.75)
*/

----------------------------------------------------------------------------------------------
