if [batch_mode] {
   # run 10000
   run -all
   quit -f

} else {
   add wave -r top_tb_v1/*
   log -r */*
   # run 10000
   run -all
}


