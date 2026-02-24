<?php

declare(strict_types=1);

namespace Drupalpod\AiLenient;

use Composer\Composer;
use Composer\IO\IOInterface;
use Composer\Package\CompletePackage;
use Composer\Package\Link;
use Composer\Package\PackageInterface;
use Composer\Plugin\PluginEvents;
use Composer\Plugin\PluginInterface;
use Composer\Plugin\PrePoolCreateEvent;
use Composer\Semver\VersionParser;
use Composer\EventDispatcher\EventSubscriberInterface;

/**
 * Composer plugin to relax drupal/ai dependency constraints.
 */
final class Plugin implements PluginInterface, EventSubscriberInterface
{
    /**
     * @var Composer
     */
    private Composer $composer;
    /**
     * @var IOInterface
     */
    private IOInterface $io;

    /**
     * {@inheritdoc}
     */
    public function activate(Composer $composer, IOInterface $io): void
    {
        $this->composer = $composer;
        $this->io = $io;
    }

    /**
     * {@inheritdoc}
     */
    public function deactivate(Composer $composer, IOInterface $io): void
    {
    }

    /**
     * {@inheritdoc}
     */
    public function uninstall(Composer $composer, IOInterface $io): void
    {
    }

    /**
     * {@inheritdoc}
     */
    public static function getSubscribedEvents(): array
    {
        return [
            PluginEvents::PRE_POOL_CREATE => 'onPrePoolCreate',
        ];
    }

    /**
     * Rewrites package constraints during pool creation when forced.
     *
     * @param \Composer\Plugin\PrePoolCreateEvent $event
     *   The Composer pool event.
     */
    public function onPrePoolCreate(PrePoolCreateEvent $event): void
    {
        if (getenv('DP_FORCE_DEPENDENCIES') !== '1') {
            return;
        }

        $lenientPackages = $this->getLenientPackages();
        if (empty($lenientPackages)) {
            return;
        }

        $constraint = $this->buildLenientConstraint();

        foreach ($event->getPackages() as $package) {
            $this->adjustPackage($package, $lenientPackages, $constraint);
        }
    }

    /**
     * Gets the list of packages to relax from environment.
     *
     * @return array
     */
    private function getLenientPackages(): array
    {
        $packages = getenv('DP_LENIENT_PACKAGES') ?: '';
        if ($packages === '') {
            return [];
        }

        return array_map('trim', explode(',', $packages));
    }

    /**
     * Check if a package should be relaxed based on patterns.
     *
     * @param string $packageName
     * @param array $lenientPackages
     * @return bool
     */
    private function shouldRelaxPackage(string $packageName, array $lenientPackages): bool
    {
        foreach ($lenientPackages as $pattern) {
            // Handle wildcard patterns (e.g., "drupal/*")
            if (strpos($pattern, '*') !== false) {
                $regex = '/^' . str_replace(['/', '*'], ['\/', '.*'], $pattern) . '$/';
                if (preg_match($regex, $packageName)) {
                    return true;
                }
            } elseif ($pattern === $packageName) {
                return true;
            }
        }
        return false;
    }

    /**
     * Builds the lenient constraint to apply across packages.
     *
     * @return \Composer\Semver\Constraint\ConstraintInterface
     */
    private function buildLenientConstraint(): \Composer\Semver\Constraint\ConstraintInterface
    {
        // Use wildcard constraint to allow any version
        return (new VersionParser())->parseConstraints('*');
    }

    /**
     * Applies the relaxed constraint to a package's requirements.
     *
     * @param \Composer\Package\PackageInterface $package
     *   The package to update.
     * @param array $lenientPackages
     *   List of packages or patterns to relax.
     * @param \Composer\Semver\Constraint\ConstraintInterface $constraint
     *   The constraint to apply.
     */
    private function adjustPackage(PackageInterface $package, array $lenientPackages, \Composer\Semver\Constraint\ConstraintInterface $constraint): void
    {
        $requires = array_map(function (Link $link) use ($lenientPackages, $constraint) {
            // Relax any drupal/* package requirements that match lenient patterns.
            if ($this->shouldRelaxPackage($link->getTarget(), $lenientPackages)) {
                return new Link(
                    $link->getSource(),
                    $link->getTarget(),
                    $constraint,
                    Link::TYPE_REQUIRE,
                    $constraint->getPrettyString()
                );
            }

            return $link;
        }, $package->getRequires());

        if ($package instanceof CompletePackage) {
            $package->setRequires($requires);
        }
    }
}
