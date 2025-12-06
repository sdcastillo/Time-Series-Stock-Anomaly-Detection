library(shiny)
library(zoo)
library(quantmod)
library(forecast)
library(lubridate)
library(ggplot2)
library(dplyr)
library(readr)

# Load the data
buffett_dividends_10y <- read_csv("MAKE-MONEY-HUSTLE.csv") %>%
  mutate(Ex_Dividend_Date = as.Date(Ex_Dividend_Date)) %>%
  arrange(Ticker, Ex_Dividend_Date)

buffett_yield_summary <- read_csv("DIVIDEND_YIELD.csv") %>%
  rename(divident_yield_percentage = `Dividend_Yield_%`) %>%
  arrange(desc(divident_yield_percentage))

# Function to fit ARIMA model, detect largest residuals, and create plot
detect_anom = function(cur_symb = "META", 
                       alpha = 0.05, 
                       start.date = "2014-01-01",
                       end.date = "2025-02-01"){  
  
  tryCatch({
    # Download stock data
    getSymbols(cur_symb, from = start.date, to = end.date, auto.assign = TRUE, env = .GlobalEnv)
    cur_data = get(cur_symb, envir = .GlobalEnv)[, 6]
    
    # Create date sequence matching actual data length
    dates = index(cur_data)
    
    # Fit model to the log of the adjusted closing price
    model = auto.arima(log(as.numeric(cur_data)))
    estimate = fitted(model)
    
    # Outliers are classified by those above the sensitivity level
    anom_index = which(residuals(model) > alpha) 
    
    if(length(anom_index) > 0){
      anom_dates = dates[anom_index]
      
      mydata = data.frame(date = dates, value = as.numeric(cur_data))
      points = data.frame(date = anom_dates, value = as.numeric(cur_data)[anom_index])
      
      point.size = pmax(residuals(model)[anom_index] * 100, 2)
      
      # Create plot
      ggplot_1 = 
        ggplot(mydata, aes(date, value)) +
        geom_line(col = "chartreuse4") + 
        geom_point(data = points, aes(date, value), size = point.size, col = "red", alpha = 0.5) + 
        geom_text(data = points, aes(date, value), hjust = 0, vjust = -0.5, 
                  label = format(points$date, "%Y-%m-%d"), size = 3) + 
        ggtitle(paste(cur_symb, "adjusted closing price")) +
        xlab("Date") + 
        ylab("Adjusted Close (USD)") + 
        theme_linedraw() + 
        theme(axis.text = element_text(size = 12),
              axis.title = element_text(size = 14, face = "bold"))
    } else {
      mydata = data.frame(date = dates, value = as.numeric(cur_data))
      ggplot_1 = 
        ggplot(mydata, aes(date, value)) +
        geom_line(col = "chartreuse4") + 
        ggtitle(paste(cur_symb, "adjusted closing price - No anomalies detected")) +
        xlab("Date") + 
        ylab("Adjusted Close (USD)") + 
        theme_linedraw()
      
      anom_dates = character(0)
    }
    
    output = list(date = anom_dates, plot = ggplot_1, model = model)  
    return(output)
    
  }, error = function(e){
    return(list(date = character(0), 
                plot = ggplot() + ggtitle(paste("Error:", e$message)),
                model = NULL))
  })
}

# Creates stock info for "details" page
stockinfo = function(ticker, date){
  tryCatch({
    start.date = ymd(date) - months(1)
    end.date = ymd(date) + months(1)
    
    getSymbols(ticker, from = start.date, to = end.date, auto.assign = TRUE, env = .GlobalEnv)
    chartSeries(get(ticker, envir = .GlobalEnv), 
                name = ticker, 
                theme = "white")
  }, error = function(e){
    plot.new()
    text(0.5, 0.5, paste("Error loading chart:", e$message))
  })
}

# Define server logic
shinyServer(function(input, output, session) {
  
  # Reactive data input
  dataInput <- reactive({
    req(input$ticker, input$dateRange)
    detect_anom(cur_symb = input$ticker,
                alpha = input$alpha,
                start.date = input$dateRange[1],
                end.date = input$dateRange[2])
  })
  
  output$distPlot <- renderPlot({
    dataInput()$plot
  })
  
  # Reactive input selection for anomaly dates
  output$selectUI <- renderUI({
    dates = dataInput()$date
    if(length(dates) > 0){
      selectInput("anomDates", "Select date", as.character(dates))
    } else {
      selectInput("anomDates", "Select date", choices = "No anomalies detected")
    }
  })
  
  output$quantPlot <- renderPlot({
    req(input$anomDates)
    if(input$anomDates != "No anomalies detected"){
      stockinfo(ticker = input$ticker, date = input$anomDates)
    } else {
      plot.new()
      text(0.5, 0.5, "No anomalies to display")
    }
  })
  
  # Chart for dividend history over time
  output$dividendHistoryPlot <- renderPlot({
    req(input$ticker)
    
    # Filter dividends for the selected ticker
    ticker_dividends <- buffett_dividends_10y |>
      filter(Ticker == input$ticker)
    
    if(nrow(ticker_dividends) > 0) {
      ggplot(ticker_dividends, aes(x = Ex_Dividend_Date, y = Amount)) +
        geom_line(col = "steelblue", linewidth = 1) +
        geom_point(col = "steelblue", size = 2) +
        ggtitle(paste(input$ticker, "- Dividend History (2015-Present)")) +
        xlab("Ex-Dividend Date") +
        ylab("Dividend Amount (USD)") +
        theme_linedraw() +
        theme(axis.text = element_text(size = 12),
              axis.title = element_text(size = 14, face = "bold"),
              plot.title = element_text(size = 16, face = "bold"))
    } else {
      ggplot() + 
        ggtitle(paste("No dividend data available for", input$ticker)) +
        theme_linedraw()
    }
  })

  # Chart for dividend yield summary comparison
  output$yieldSummaryPlot <- renderPlot({
    top_n <- 30

    plot_data <- buffett_yield_summary %>%
      arrange(desc(divident_yield_percentage)) %>%
      slice_head(n = top_n) %>%
      mutate(Ticker = reorder(Ticker, divident_yield_percentage))

    ggplot(plot_data, aes(x = Ticker, y = divident_yield_percentage)) +
      geom_col(aes(fill = Ticker), show.legend = FALSE) +
      geom_point(color = "black", size = 2) +
      coord_flip() +
      scale_fill_brewer(palette = "Set3") +
      ggtitle(paste("Top", top_n, "Dividend Yield Comparison (TTM)")) +
      xlab("Ticker") +
      ylab("Dividend Yield (%)") +
      theme_linedraw() +
      theme(axis.text.y = element_text(size = 9))
  })
  
})