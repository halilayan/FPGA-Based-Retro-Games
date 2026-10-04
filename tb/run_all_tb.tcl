## run_all_tb.tcl
##
## Regresyon simulasyon calistiricisi.
## TB_LIST'teki her testbench icin: dosya henuz yoksa atla (o modul henuz
## yazilmadi demektir), varsa disk uzerinde tek kullanimlik bir proje kurup
## behavioral simulasyon calistirir.
##
## PASS/FAIL TESPITI BURADA YAPILMAZ: her testbench, simulasyon sonunda
## tam olarak tek bir ozet satiri basar:
##   report "<tb_adi>: PASS - ..." severity note;   -- basarili
##   report "<tb_adi>: FAIL - ..." severity failure; -- basarisiz
## Bu satirlar Vivado konsol ciktisina (xsim report ciktisi) dogrudan yazilir;
## gercek PASS/FAIL sayimi bu ciktidan "<tb>: PASS"/"<tb>: FAIL" desenleri
## aranarak yapilir.
##
## Kullanim (tek basina, elle, repo kokunden):
##   vivado -mode batch -source tb/run_all_tb.tcl
##
## Yeni bir modul + testbench eklendikce, TB_LIST'e adini ekleyin (uzantisiz,
## sadece entity adi, ör. "tb_vga_sync").

set TB_LIST {
    tb_blink
    tb_sync_2ff
    tb_clk_pix_gen
    tb_vga_sync
    tb_fb_reader
    tb_palette_lut
    tb_video_out
    tb_debounce
    tb_scancode_fifo
    tb_ps2_rx
    tb_fb_ram
    tb_kbd_to_pad
    tb_kbd_axi_if
    tb_digit_font
    tb_palette_init
    tb_fb_arbiter
    tb_axi_bram_byte_adapter
    tb_fb_pattern_writer
    tb_vga_test_top
    tb_kbd_test_top
    tb_blitter
    tb_console_gpu_axi
    tb_collision
    tb_cart_slot
    tb_asset_rom
}

## Testbench dosyasi disindaki tum RTL kaynaklarinin arandigi klasorler
set RTL_DIRS {
    hdl/common
    hdl/video
    hdl/input
    hdl/gpu
    hdl/cart
    hdl/cart/games
    hdl/tops
}

## Her TB icin kullanilip atilacak, disk uzerindeki gecici proje kok dizini
set SCRATCH_ROOT "build/sim_runs"

set SKIP_COUNT 0
set TOOL_ERROR_COUNT 0

foreach tb $TB_LIST {
    set tb_file "tb/${tb}.vhd"

    if {![file exists $tb_file]} {
        puts "ATLA   : $tb  (henuz yazilmadi: $tb_file yok)"
        incr SKIP_COUNT
        continue
    }

    puts "----------------------------------------------------------------"
    puts "CALISIYOR: $tb"
    puts "----------------------------------------------------------------"

    catch {close_sim}
    catch {close_project}

    ## Her TB icin disk uzerinde temiz, tek kullanimlik bir proje
    set proj_dir "${SCRATCH_ROOT}/${tb}"
    file delete -force $proj_dir
    create_project -force $tb $proj_dir -part xc7a35tcpg236-1

    ## Ortak/gpu/video/... RTL kaynaklarini ekle (varsa)
    foreach d $RTL_DIRS {
        if {[file isdirectory $d]} {
            set files [glob -nocomplain -directory $d *.vhd]
            if {[llength $files] > 0} {
                add_files -norecurse $files
            }
        }
    }

    ## Bus/protokol fonksiyonel modelleri (varsa)
    set bfm_files {}
    if {[file isdirectory tb/bfm]} {
        set bfm_files [glob -nocomplain -directory tb/bfm *.vhd]
        if {[llength $bfm_files] > 0} {
            add_files -norecurse $bfm_files
        }
    }

    ## Testbench dosyasinin kendisi
    add_files -norecurse $tb_file

    ## DIL SURUMU (2026-09-18 karari):
    ##   RTL  -> duz VHDL (1076-93). Vivado IP Integrator'un "Add Module"
    ##           (RTL modul referansi) akisi VHDL-2008 kaynak KABUL ETMEZ;
    ##           Block Design'a girebilecek her modul 93 uyumlu olmalidir.
    ##   TB/BFM -> VHDL-2008 (std.env.stop gibi 2008 ozellikleri kullanirlar,
    ##           ve asla Block Design'a girmezler).
    set_property file_type {VHDL} [get_files *.vhd]
    if {[llength $bfm_files] > 0} {
        set_property file_type {VHDL 2008} [get_files $bfm_files]
    }
    set_property file_type {VHDL 2008} [get_files $tb_file]
    set_property top $tb [get_filesets sim_1]
    update_compile_order -fileset sim_1

    ## launch_simulation koseli otomatik olarak projenin
    ## xsim.simulate.runtime ozelligi kadar (varsayilan 1000ns) BASTAN bir
    ## kez calistirir - asagidaki "run -all" bundan BAGIMSIZ, IKINCI bir
    ## calistirma. Bir TB kendi std.env.stop'una bu ilk 1000ns icinde
    ## ulasirsa (hizli TB'lerin cogu), "run -all" onu bir DAHA calistirir;
    ## ama testbench artik dogru sekilde "stop; wait;" ile kalici olarak
    ## askida kaldigindan (2026-09-21'de duzeltildi),
    ## std.env.stop bir daha HICBIR ZAMAN tetiklenmez - saat ureteci
    ## (`clk <= not clk after ...;`) ise sonsuza dek olay uretmeye devam
    ## eder, "run -all" da bu yuzden GERCEKTEN SONSUZA DEK doner (dakikada
    ## ~1 GB'lik bosa dalga formu (.wdb) dokumu ile birlikte - gercek
    ## donanim hatasi degil, sadece bu iki calistirmanin ust uste binmesi).
    ## Runtime'i 0ns'e sabitleyerek launch_simulation'in kendi otomatik
    ## calistirmasi iptal edilir; asagidaki "run -all" boylece HER TB icin
    ## TEK ve YETERLI calistirma olur.
    set_property -name {xsim.simulate.runtime} -value {0ns} -objects [get_filesets sim_1]

    if {[catch {launch_simulation} sim_err]} {
        puts "ARAC HATASI: $tb simulasyonu baslatilamadi -> $sim_err"
        incr TOOL_ERROR_COUNT
    } else {
        ## TB kendi kendine std.env.stop ile durur
        if {[catch {run -all} run_err]} {
            puts "ARAC HATASI: $tb calisirken hata -> $run_err"
            incr TOOL_ERROR_COUNT
        }
        catch {close_sim}
    }

    catch {close_project}
}

puts "================================================================"
puts "run_all_tb.tcl bitti: ATLANAN $SKIP_COUNT, ARAC HATASI $TOOL_ERROR_COUNT"
puts "(gercek PASS/FAIL sayimi yukaridaki konsol ciktisinda \"<tb>: PASS\"/\"<tb>: FAIL\" desenleri aranarak yapilir)"
puts "================================================================"

if {$TOOL_ERROR_COUNT > 0} {
    exit 1
}
exit 0
