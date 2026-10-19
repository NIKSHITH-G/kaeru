# Kaeru website

The landing page at https://getkaeru.vercel.app, built with Next.js and deployed on Vercel.

```bash
npm install
npm run dev      # http://localhost:3000
```

Pushing to `main` deploys the site automatically: the Vercel project "kaeru" is connected to this repo with Root Directory `website`.

`app/components/WheelDemo.tsx` is the interactive wheel demo. Its colours match `Sources/Kaeru/UI/Theme.swift` in the app.
