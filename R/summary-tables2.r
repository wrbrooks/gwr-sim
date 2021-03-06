library(brooks)
library(dplyr)

#The simulation parameters
rho = rep(c(rep(0, 2), rep(0.5, 2), rep(0.9, 2)), 6) #rho is the correlation of the covariates
sigma.tau = rep(0, 18) #sigma.tau is the spatial autocorrelation range parameter of the noise term
sigma = rep(c(0.5, 1), 9) #sigma is the variance of the noise term
size = c(rep(100, 6), rep(200, 6), rep(400, 6))
params = data.frame(rho, sigma.tau, sigma, size)

#Row prefix for simulation tables
sim.prefix <- list()
sim.prefix$pos <- sapply(0:17, function(x) return(x), simplify=FALSE)
sim.prefix$command <- c("\\multirow{6}{*}{100} & \\multirow{2}{*}{0} & 0.5 & ",
                        " &  & 1.0 & ",
                        " & \\multirow{2}{*}{0.5} & 0.5 & ",
                        " &  & 1.0 & ",
                        " & \\multirow{2}{*}{0.9} & 0.5 & ",
                        " &  & 1.0 & ",
                        "\\hline \\multirow{6}{*}{200} & \\multirow{2}{*}{0} & 0.5 & ",
                        " &  & 1.0 & ",
                        " & \\multirow{2}{*}{0.5} & 0.5 & ",
                        " &  & 1.0 & ",
                        " & \\multirow{2}{*}{0.9} & 0.5 & ",
                        " &  & 1.0 & ",
                        "\\hline \\multirow{6}{*}{400} & \\multirow{2}{*}{0} & 0.5 & ",
                        " &  & 1.0 & ",
                        " & \\multirow{2}{*}{0.5} & 0.5 & ",
                        " &  & 1.0 & ",
                        " & \\multirow{2}{*}{0.9} & 0.5 & ",
                        " &  & 1.0 & ")

#Table of MISE for each beta for each setting/method combination
table.MISE.beta = matrix(NA, 18, 8)

for (process in 1:6) {
for (i in 1:3) {
aa = matrix(NA, 0, 8)
for (b in 1:5) {

#for (j in 1:18) {
    j = (b-1)*3*6 + (i-1)*6 + process
    row = vector()
    for (beta in 1:4) {
        for (method in c('lagr', 'gwr')) {
            row = c(row, MISEX[[method]][[j]][[beta]])
        }
    }
    aa = rbind(aa, row)
}
    table.MISE.beta[(i-1)*6 + process,] = colMeans(aa)
}

}


#Which elements to highlight:
bold.beta = matrix(FALSE, 18, 8)
for (beta in 1:4) {
    indx = (beta-1) * 2 + (1:2)
    subtable = table.MISE.beta[,indx]
    
    for (i in 1:18) {
        bold.beta[i,indx[which.min(subtable[i,])]] = TRUE
    }
}

xtable.printbold(xtable(table.MISE.beta), which.bold=bold.beta, hline.after=NULL,
                 only.contents=TRUE,
                 include.rownames=FALSE,
                 include.colnames=FALSE,
                 add.to.row=sim.prefix)



#Table of zero frequencies
table.zero.freq = matrix(NA, 18, 4)

for (process in 1:6) {
for (i in 1:3) {
aa = matrix(NA, 0, 4)
for (b in 1:5) {

#for (j in 1:18) {
    j = (b-1)*3*6 + (i-1)*6 + process
    row = vector()
    for (beta in 1:4) {
            row = c(row, freq.zero[[j]][[beta]] %>% round(2))
    }
    aa = rbind(aa, row)
}
table.zero.freq[(i-1)*6 + process,] = colMeans(aa)
}
}


#Table of MISE for Y
table.MISE.Y = matrix(NA, 0, 2)

for (i in 1:18) {
    row = vector()
        for (method in c('lagr', 'gwr')) {
            row = c(row, MISEY[[method]][[i]] %>% round(2))
        }
    table.MISE.Y = rbind(table.MISE.Y, row)
}

#Which elements to highlight:
bold.Y = matrix(FALSE, 18, 2)
for (i in 1:18) {
    if (i %% 2 == 1) {truth = 0.5}
    else {truth = 1}
    bold.Y[i,which.min(abs(table.MISE.Y[i,] - truth))] = TRUE
}

xtable.printbold(xtable(cbind(table.zero.freq, table.MISE.Y)), which.bold=cbind(matrix(FALSE, 18,4),bold.Y), hline.after=NULL,
                 only.contents=TRUE,
                 include.rownames=FALSE,
                 include.colnames=FALSE,
                 add.to.row=sim.prefix)



print(xtable(table.zero.freq), hline.after=NULL,
                 only.contents=TRUE,
                 include.rownames=FALSE,
                 include.colnames=FALSE,
                 add.to.row=sim.prefix)