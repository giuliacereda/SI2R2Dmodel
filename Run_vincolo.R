rm(list=ls())

mainDir<-dirname(rstudioapi::getActiveDocumentContext()$path) #here put the path to the folder
 
setwd(mainDir)

dir.create(file.path(mainDir, "Figures"), showWarnings = FALSE)

dir.create(file.path(mainDir, "WS"), showWarnings = FALSE)


vuoi.parallelizzare=1
n.cores=16
n.boot=100
quanti.punti.iniziali=100
#p_seq<-0.0078


source(file = "Functions_vincolo.R")
library(foreign)
library(parallel)
library(xtable())
library(optimr) 
library(splines)
library(future.apply)
library(future)
library(nloptr)
################################
#       data import
################################

data.ini<-"2020-08-01T17:00:00"
data.exit<-"2021-01-31T17:00:00" #here you can choose till when you want to calibrate
  
names <- c("date", "country", "cod_reg", "region", "lat", "longit", "ricoverati_sintom", "terint", "ricoverati_tot",
           "isolamento", "positivi","variazione_totale_positivi", "nuovi_pos", "dimessi_guariti", "deceduti", "casi_da_sospetto_diagnostico","casi_da_screening", "tot_casi", "tamponi")
DATA <- read.csv(file = "https://raw.githubusercontent.com/pcm-dpc/COVID-19/master/dati-regioni/dpc-covid19-ita-regioni.csv", stringsAsFactors = FALSE)
colnames(DATA) <- names
REG<-unique(DATA$region)
 

DATA[DATA$region %in% c("P.A. Bolzano"  , "P.A. Trento"),]$region<-rep("Trentino", length(DATA[DATA$region %in% c("P.A. Bolzano"  , "P.A. Trento"),]$region))

order(unique(DATA$lat))

DATA[DATA$region %in% c("Trentino"),]$lat<-mean(DATA[DATA$region %in% c("Trentino"),]$lat)


S0.vec<- c("Abruzzo"=1305770, "Basilicata"=556934, "Calabria"=1924701, "Campania"=5785861,
           "Emilia-Romagna"=4467118, "Friuli-Venezia Giulia"=1211357, "Lazio"=5865544,
           "Liguria"=1543127, "Lombardia"=10103969, "Marche"=1518400, "Molise"=302265,
           "Trentino"= 1074819,"Piemonte"=4356406, "Puglia"=4008296,
           "Sardegna"=1630474, "Sicilia"=4968410, "Toscana"=3737000, "Umbria"=880285,
           "Valle d'Aosta"=125501, "Veneto"=4907704)


REG<-unique(DATA$region)
REG_order<-REG[order(unique(DATA$lat))]

# initial points grid
r0.0<-seq(0.5,5,0.5)
r0.1<-seq(-5,5,1)  
r0.2<-seq(-5,5,1)  
r0.3<-seq(-5,5,1)  
r0.4<-seq(-5,5,1)   
r0.5<-seq(-5,5,1)   
r0.6<-seq(-5,5,1)   
r0.7<-seq(-5,5,1)   
set.seed(12)
R00<-sample(seq(0.1,5,0.1), quanti.punti.iniziali, replace=TRUE)
R01<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)
R02<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)
R03<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)
R04<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)
R05<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)
R06<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)
R07<-sample(seq(-5,5,0.1), quanti.punti.iniziali, replace=TRUE)

#par_all<-cbind(p_seq, R00,R01, R02,R03,R04,R05,R06,R07,dinf,dmort)

p_seq<-0.0078 #IFR

dinf<-14   #time to recovery 
dmort<-14  #time to death

par_all<-cbind(p_seq, R00,R01, R02,R03,R04,R05,R06,R07,dinf,dmort)

pesi=c(1,0,0)
#par_all<-as.matrix(expand.grid(p_seq,r0.0, r0.1,r0.2,r0.3,r0.4,r0.5,r0.6,r0.7, dinf,dmort))


############################################################
#       create the list of deaths (morti) and positive at 31/07 (positivi.ini) for all Regions
############################################################
 
morti<-list()
positivi.ini<-list()
for (g in 1:20){ 
  Regione<-REG[g]
  S.0<-S0.vec[g]
  print(S.0)
  data <- DATA[DATA$region==Regione,] 
  i0<-data$positivi[data$date==(as.Date(data.ini)-1)] # altrove  nel boot
  data$deceduti<-data$deceduti-data$deceduti[data$date==(as.Date(data.ini)-1)]
  data<- data[which(data$date<=data.exit & data$date>=data.ini),]
  obs.dead<-data$deceduti
  
  if(g==12){
    obs.dead<-aggregate(data$deceduti, by =list(data$date), sum)$x
    i0<-sum(i0)
  }
  t.o<-length(obs.dead)
  if(g==5){
    obs.dead<- obs.dead+c(rep(0, 14), rep(-154, t.o-14)) 
  }
  
  morti[[g]]=obs.dead
  positivi.ini[[g]]=i0
}

 

########################################
#      ciclo vecbest regioni          #
########################################


VEC<-list()
VEC.ini<-list()
tempo.reg<-list()
griglia_tempo<-list()

for (g in 1:20){

Regione<-REG[g]
S.0<-S0.vec[g]
obs.dead<-morti[[g]]
i0<-positivi.ini[[g]]
#set.seed(12)
#ggg<- sample(1:(dim(par_all)[1]), size = quanti.punti.iniziali)

lower<-c(p_seq, 0,-10,-10,-10,-10,-10,-10, -10,14,14) 
upper<-c(p_seq, 7, 20, 20, 20, 20, 20,20,20, 14,14)


#bdmsk.gc<- c(0,1,1,1,1,1,1,1, 0,0)

#fop.bootx<-function(vec_p){
#  x <- Rvmmin::Rvmmin(vec_p, optim.parallel.ns_dev,  lower=lower, upper=upper, bdmsk=bdmsk.gc,control=list(maxit=10^4))
#  return(list(x$value, x$convergence, x$counts, x$par))
#}

fop.bootx<-function(vec_p){
  x <- nloptr::auglag(vec_p,fn =optim.parallel.ns_dev,localtol = 1e-08,localsolver = 'LBFGS',control = list(maxeval = 10^4,xtol_rel = 1e-08),hin =  hin,lower=lower,upper=upper)
  return(list(x$value, x$iter, x$par))
}


hin <- function(par_all) {
  w =nspline.r0(knots = NULL,par_all[2:9],N = t.o)
  return(w)
}


#hin2 <- function(par_all) {
 # w =nspline.r0(knots = NULL,par_all[2:9],N = t.o)
#  return(list(ceq=NULL, c=-w))
#}



t1<-Sys.time()
plan(multiprocess, workers = n.cores)
s<-future.apply::future_apply(par_all,1,FUN = fop.bootx )
t2<-Sys.time()
t2-t1
griglia_tempo[[g]]<-t2-t1
  


sv<-unlist(lapply(s, function(x) x[[1]]))

 
mins<-which(sv==min(sv))[1]
spar = matrix(NA,quanti.punti.iniziali,11)
for(i in 1:quanti.punti.iniziali){
  spar[i,] = s[[i]][[3]]
}


vec_best<-spar[mins, ]
 
sim_best<-optim.parallel.ns(as.numeric(vec_best), i0=i0, kp=kp, obs=obs.dead,  ####QUA###
                       last.day= data.exit, pesi=pesi,  per.opm=0)
VEC[[g]]<-as.numeric(vec_best)
VEC.ini[[g]]<-par_all
print(REG[g])
t2<-Sys.time()
 
tempo.reg[[g]]<-t2-t1
 
}   

#matrice dei VEC stimati
#cbind(REG, t(matrix(as.numeric(round(unlist(VEC), digits = 3)), ncol=20)))


 
########################################################
# BOOTSTRAP 
#########################################################
#####
#source("Functions_vincolo.R")
####################################
par_boot<-list()
tempo_boot<-list()
list.out<-list()

 
for (g in 1:20){
 
  t1<-Sys.time()
  Regione<-REG[g]
  S.0<-S0.vec[g]
  obs.dead=morti[[g]]
  i0<-positivi.ini[[g]]
    sim<- optim.parallel.ns(VEC[[g]], i0=i0, kp=kp, obs=obs.dead,  ####QUA###
                          last.day= data.exit, pesi=pesi,  per.opm=0)
D.est<-sim$D
decessi.new.prima.morto<-1
vec_parameters=VEC[[g]] #cambiato qua : prima c era il punto iniziale
MAT.D<-boot.SIRD(n.boot, D.est,i0, decessi.new.prima.morto=1, epsilon=1)
m2<-MAT.D$mat.boot.D
 
trials <- 1:n.boot
parameters.boot<-matrix(0, n.boot,length(vec_best))

lower<-c(p_seq,vec_parameters[2:9]-20, 14, 14)
upper<-c(p_seq,vec_parameters[2:9]+20, 14, 14)

#lower<-c(p_seq, 0,-10,-10,-10,-10,-10,-10, -10,14,14) 
#upper<-c(p_seq, 7, 20, 20, 20, 20, 20,20,20, 14,14)

#lower<-c(p_seq, 0.1,-5,-3,-3,-3,-3, -5, -3,14,14) 
#upper<-c(p_seq, 7, 5, 3, 3, 3, 3, 5,3, 14,14)



#lb[2]<-max(0, lb[2])
 

plan(multiprocess, workers = n.cores)
output<-future.apply::future_apply(m2, 2,boot.calibr.par2)

parameters.boot<-matrix(0, n.boot, length(vec_parameters))
for(j in 1:n.boot){
  parameters.boot[j,]<-output[[j]]$parameters
   }

#boot.calibr.par2(m2[,1])

 
MAT.COEFF.SPLINE<-matrix(rep(NA, n.boot*8),nrow=n.boot)
MAT.SPLINE<-matrix(rep(NA, n.boot*length(obs.dead)),nrow=n.boot)

MAT.COEFF.SPLINE<-parameters.boot[,2:9]
for(i in 1:n.boot){
MAT.SPLINE[i,]<-nspline.r0(coeff=MAT.COEFF.SPLINE[i,], N=length(obs.dead))
}
 

par_boot[[g]]<-parameters.boot
list.out[[g]]<-MAT.SPLINE
print(REG[g])
t2<-Sys.time()
tempo_boot[[g]]<-t2-t1
 
}   
 

#paste("/Figures/", paste(paste(paste(as.character(n.boot), "boot", sep=""),paste(substr(as.character(p_seq), 3, 7), "p", sep="") ,paste(substr(as.character(data.exit),9, 10),substr(as.character(data.exit),6, 7), sep=""),sep="_"), ".Rdata", sep=""), sep="")
setwd(file.path(mainDir, "WS"))
 
save.image(paste(paste(paste(as.character(n.boot), "boot", sep=""),paste(substr(as.character(p_seq), 3, 7), "p", sep="") ,paste(substr(as.character(data.exit),9, 10),substr(as.character(data.exit),6, 7), sep=""),"vncl",sep="_"), ".Rdata", sep=""))
  
setwd(mainDir)

