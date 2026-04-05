import express, { Express, Request, Response, NextFunction } from 'express';

const app: Express = express();
const PORT: number = parseInt(process.env.PORT || '3000', 10);

// Middleware
app.use(express.json());

// Routes
app.get('/', (req: Request, res: Response): void => {
  res.json({ message: 'Welcome to Toast Backend API' });
});

app.get('/health', (req: Request, res: Response): void => {
  res.json({ status: 'ok' });
});

// Error handling middleware
app.use((err: Error, req: Request, res: Response, next: NextFunction): void => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal Server Error' });
});

// Start server
app.listen(PORT, (): void => {
  console.log(`Server running on port ${PORT}`);
});

export default app;
