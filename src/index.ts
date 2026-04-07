import express, { Express, Request, Response } from 'express';

const app: Express = express();
const port: number = process.env.PORT ? parseInt(process.env.PORT, 10) : 3000;

// Middleware
app.use(express.json());

// Routes
app.get('/', (req: Request, res: Response) => {
  res.json({ message: 'Welcome to Toast Backend API' });
});

app.get('/health', (req: Request, res: Response) => {
  res.json({ status: 'healthy' });
});

// Error handling middleware
app.use((err: Error, req: Request, res: Response) => {
  console.error(err.stack);
  res.status(500).json({ error: 'Internal Server Error' });
});

// Start server
app.listen(port, () => {
  console.log(`Server running at http://localhost:${port}`);
});
