class AppError extends Error {
  constructor(message, status = 400) {
    super(message);
    this.status = status;
  }
}

/** Express error handler — register last */
function errorHandler(err, req, res, next) {
  const status  = err.status  || 500;
  const message = err.message || 'Internal server error';
  res.status(status).json({ error: message });
}

module.exports = { AppError, errorHandler };
