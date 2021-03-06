source("./07.model.functions.R")
p_load(glmnet)

# Functions ---------------------------------------------------------------

glm.looq2 <- function(read.dir, nsplits, a, max) {
  trn.split <- 1:nsplits
  q2.results <- c(rep(0.0, nsplits))
  if(str_detect(read.dir, "alpha"))
    features <- readRDS("./feature.selection/alpha.vars.RDS")
  else if(str_detect(read.dir, "beta"))
    features <- readRDS("./feature.selection/beta.vars.RDS")
  else
    features <- readRDS("./feature.selection/gamma.vars.RDS")
  for(n in 1:nsplits) {
    data <- readRDS(paste0(read.dir, n, "/pp.RDS")) %>%
      select(., -guest)
    obs <- data[ , 1]
    data <- data %>% select(., DelG, one_of(features)) %>%
      data.matrix()
    pred <- c(rep(0.0, nrow(data) - 1))
    # In this loop, i represents the index of the datapoint left out of 
    # model building
    for(i in 1:nrow(data)) {
      trn <- data[-i, ]
      tst <- data[i, , drop = F]
      trn.x <- trn[ , -1]
      trn.y <- trn[ , 1]
      tst.x <- tst[ , -1, drop = F]
      tst.y <- tst[ , 1, drop = F]
      
      # Refer to 07.0.1.svm.tune.poly.R for values
      glm.mod <- glmnet(x = trn.x, y = trn.y, 
                        dfmax = max, alpha = a,
                        pmax = ncol(trn.x), 
                        family = "mgaussian")
      pred[i] <- predict.glmnet(glm.mod, tst.x,
                                s = tail(glm.mod$lambda, n = 1)) 
    }
    # test.df <- data.frame(obs, pred) %>% print()
    # test.df <<- test.df
    # defaultSummary(test.df) %>% print()
    # prediction error sum of squares
    pred.df <- data.frame(obs, pred)
    p <- ggplot(pred.df, aes(x = obs, y = pred)) + 
      theme_bw() + 
      geom_point() + 
      labs(title = n) + 
      geom_abline(intercept = 0, slope = 1) + 
      coord_fixed()
    print(p)
    # Handling outliers
    for(i in 1:length(pred)) {
      if(pred[i] < -100)
        pred[i] <- mean(obs)
    }
    PRESS <- sum((obs - pred)^2)
    # total sum of squares
    TSS <- sum((obs - mean(obs))^2)
    q2 <- 1 - PRESS/TSS
    message("Q2 = ", q2)
    q2.results[n] <- q2
  }
  return(data.frame(trn.split, q2.results))
}

glm.tst <- function(pp.dir, tst.dir, nsplits, a, max) {
  if(str_detect(pp.dir, "alpha"))
    features <- readRDS("./feature.selection/alpha.vars.RDS")
  else if(str_detect(pp.dir, "beta"))
    features <- readRDS("./feature.selection/beta.vars.RDS")
  else
    features <- readRDS("./feature.selection/gamma.vars.RDS")
  results.all <- data.frame()
  
  for(i in 1:nsplits) {
    # Reading the training data
    trn <- readRDS(paste0(pp.dir, i, "/pp.RDS")) %>%
      select(., -guest)
    trn.x <- select(trn, one_of(features)) %>% data.matrix()
    trn.y <- select(trn, DelG) %>% data.matrix()
    glm.mod <- glmnet(x = trn.x, y = trn.y, 
                      dfmax = max, alpha = a,
                      pmax = ncol(trn.x), 
                      family = "mgaussian")
    tst.all <- data.frame()
    for(j in 1:nsplits) {
      tst <- preprocess.tst.mod(pp.dir = pp.dir, tst.dir = tst.dir, 
                                feat = colnames(trn.x), n = j)
      tst.y <- data.matrix(tst)[ , 1, drop = F]
      tst.x <- data.matrix(tst)[ , -1]
      tst.df <- predict.glmnet(glm.mod, newx = tst.x, 
                               s = tail(glm.mod$lambda, n = 1)) %>%
        cbind(tst.y, .) %>%
        as.data.frame()
      colnames(tst.df) <- c("obs", "pred")
      tst.df <- tst.df %>% mutate(split = j)
      
      for(k in 1:nrow(tst.df))
        if(abs(tst.df$pred[k]) > 100)
          tst.df$pred[k] <- mean(trn.y)
      
      results.tst <- data.frame(trn.split = i, tst.split = j, 
                                r2 = defaultSummary(tst.df)[2], 
                                rmse = defaultSummary(tst.df)[1])
      results.all <- rbind(results.all, results.tst)
      tst.all <- rbind(tst.all, tst.df)
    }
  
    tst.all$split <- as.factor(tst.all$split)
    p <- ggplot(tst.all, aes(x = obs, y = pred, color = split)) + 
      geom_point() + 
      theme_bw() + 
      labs(title = i) + 
      geom_abline(slope = 1, intercept = 0) + 
      coord_fixed()
    print(p)
  }
  row.names(results.all) <- NULL
  return(results.all)
}

glm.tst.splits <- function(pp.dir, tst.dir, feat, nsplits, model) {
  tst.all <- data.frame()
  for (j in 1:nsplits) {
    tst <- preprocess.tst.mod(pp.dir = pp.dir, tst.dir = tst.dir, 
                              feat = feat, n = j) 
    tst.y <- data.matrix(tst)[ , 1, drop = F]
    tst.x <- data.matrix(tst)[ , -1]
    
    tst.df <- predict.glmnet(model, tst.x, 
                             s = tail(model$lambda, n = 1)) %>%
      cbind(tst.y, .) %>% as.data.frame() 
    colnames(tst.df) <- c("obs", "pred")
    tst.df <- tst.df %>% mutate(split = j)
    
    for(k in 1:nrow(tst.df))
      if(abs(tst.df$pred[k]) > 100)
        tst.df$pred[k] <- mean(trn.y)
    
    tst.all <- rbind(tst.all, tst.df)
  }
  tst.all$split <- as.factor(tst.all$split)
  return(tst.all)
}

# Alpha ----
#   LOO-CV ----

# 1, 4, 5, 6, 8, 10
glm.looq2("./pre-process/alpha/", nsplits = 10, a = 0.6, max = 13)

#   Test ----

# None pass, best is 8
alpha.tst <- glm.tst("./pre-process/alpha/", "./model.data/alpha/", 
                     nsplits = 10, a = 0.6, max = 13) 
alpha.1to1 <- alpha.tst %>% filter(trn.split == tst.split) %>% print()
alpha.avg <- avg.tst(alpha.tst) %>% print()

#    Model ----

trn.alpha <- readRDS("./pre-process/alpha/8/pp.RDS") %>%
  select(., -guest)
features <- readRDS("./feature.selection/alpha.vars.RDS")
colnames(trn.alpha) <- str_replace(colnames(trn.alpha), "-", ".")
trn.alpha <- trn.alpha %>% select(., DelG, features) 
trn.alpha.x <- select(trn.alpha, -DelG) %>% data.matrix()
trn.alpha.y <- trn.alpha$DelG %>% data.matrix()

glm.alpha <- glmnet(x = trn.alpha.x, 
                    y = trn.alpha.y, 
                    alpha = 0.6, 
                    dfmax = 13, 
                    family = "mgaussian")
tst.alpha.df <- glm.tst.splits("pre-process/alpha/", "model.data/alpha/", 
                               features, 10, glm.alpha)
tst.alpha.df2 <- tst.alpha.df %>% filter(split == "8")

eval.tropsha(tst.alpha.df)
eval.tropsha(tst.alpha.df2)

#   Save ----

saveRDS(tst.alpha.df, "./results/alpha/glmnet.all.RDS")
saveRDS(tst.alpha.df2, "./results/alpha/glmnet.RDS")

# Beta ----

#   LOO-CV ----
# 1, 4, 5, 9
glm.looq2("./pre-process/beta/", nsplits = 10, a = 1, max = 10)

#   Test ----

# None pass but 3 is the best
beta.tst <- glm.tst("./pre-process/beta/", "./model.data/beta/", 
                     nsplits = 10, a = 1, max = 10) 
beta.1to1 <- beta.tst %>% filter(trn.split == tst.split) %>% print()
beta.avg <- avg.tst(beta.tst) %>% print()

#    Model ----

trn.beta <- readRDS("./pre-process/beta/3/pp.RDS") %>%
  select(., -guest)
features <- readRDS("./feature.selection/beta.vars.RDS")
colnames(trn.beta) <- str_replace(colnames(trn.beta), "-", ".")
trn.beta <- trn.beta %>% select(., DelG, features) 
trn.beta.x <- select(trn.beta, -DelG) %>% data.matrix()
trn.beta.y <- trn.beta$DelG %>% data.matrix()

glm.beta <- glmnet(x = trn.beta.x, 
                    y = trn.beta.y, 
                    alpha = 1, 
                    dfmax = 10, 
                    family = "mgaussian")
tst.beta.df <- glm.tst.splits("pre-process/beta/", "model.data/beta/", 
                               features, 10, glm.beta)
tst.beta.df2 <- tst.beta.df %>% filter(split == "3")

eval.tropsha(tst.beta.df)
eval.tropsha(tst.beta.df2)

#   Save ----

saveRDS(tst.beta.df, "./results/beta/glmnet.all.RDS")
saveRDS(tst.beta.df2, "./results/beta/glmnet.RDS")

# Gamma ----

#   LOO-CV ----
glm.looq2("./pre-process/gamma/", nsplits = 10, a = 0.7, max = 20) 

#   Test ----

# None pass, 4 is the best
gamma.tst <- glm.tst("./pre-process/gamma/", "./model.data/gamma/", 
                    nsplits = 10, a = 0.7, max = 20) 
gamma.1to1 <- gamma.tst %>% filter(trn.split == tst.split) %>% print()
gamma.avg <- avg.tst(gamma.tst) %>% print()

#    Model ----

trn.gamma <- readRDS("./pre-process/gamma/4/pp.RDS") %>%
  select(., -guest)
features <- readRDS("./feature.selection/gamma.vars.RDS")
colnames(trn.gamma) <- str_replace(colnames(trn.gamma), "-", ".")
trn.gamma <- trn.gamma %>% select(., DelG, features) 
trn.gamma.x <- select(trn.gamma, -DelG) %>% data.matrix()
trn.gamma.y <- trn.gamma$DelG %>% data.matrix()

glm.gamma <- glmnet(x = trn.gamma.x, 
                   y = trn.gamma.y, 
                   alpha = 0.7, 
                   dfmax = 20, 
                   family = "mgaussian")
tst.gamma.df <- glm.tst.splits("pre-process/gamma/", "model.data/gamma/", 
                              features, 10, glm.gamma)
tst.gamma.df2 <- tst.gamma.df %>% filter(split == "4")

eval.tropsha(tst.gamma.df)
eval.tropsha(tst.gamma.df2)

#   Save ----

saveRDS(tst.gamma.df, "./results/gamma/glmnet.all.RDS")
saveRDS(tst.gamma.df2, "./results/gamma/glmnet.RDS")