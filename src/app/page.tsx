import { BrandMark } from "@/components/brand-mark";

// Placeholder home page for slice 0. The full landing page and application
// arrive in slice 2, with copy drafted for your review.
export default function Home() {
  return (
    <main className="flex flex-1 flex-col">
      <header className="bg-stage px-6 py-6 sm:px-14">
        <BrandMark />
      </header>
      <section className="mx-auto flex w-full max-w-5xl flex-1 flex-col justify-center gap-6 px-6 py-16 sm:px-14">
        <p className="cce-label text-metadata">CCE Talent Network</p>
        <h1 className="cce-display">Develop People. Build Better Systems.</h1>
        <div className="h-[3px] w-16 bg-sunbeam" aria-hidden="true" />
        <p className="cce-lead max-w-2xl">
          The application is being built. Check back soon.
        </p>
      </section>
    </main>
  );
}
