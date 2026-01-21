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
     * Rewrites drupal/ai constraints during pool creation when forced.
     *
     * @param \Composer\Plugin\PrePoolCreateEvent $event
     *   The Composer pool event.
     */
    public function onPrePoolCreate(PrePoolCreateEvent $event): void
    {
        if (getenv('DP_FORCE_DEPENDENCIES') !== '1') {
            return;
        }

        $constraint = $this->buildAiConstraint();
        if ($constraint === null) {
            return;
        }

        foreach ($event->getPackages() as $package) {
            $this->adjustPackage($package, $constraint);
        }
    }

    /**
     * Builds the drupal/ai constraint to apply across packages.
     *
     * @return \Composer\Semver\Constraint\ConstraintInterface|null
     */
    private function buildAiConstraint(): ?\Composer\Semver\Constraint\ConstraintInterface
    {
        $version = getenv('DP_AI_MODULE_VERSION') ?: '';
        $major = $this->extractMajorVersion($version);
        $constraint = $major !== '' ? '^' . $major : '*';
        return (new VersionParser())->parseConstraints($constraint);
    }

    /**
     * Extracts the major version from a version string.
     *
     * @param string $version
     *   The version string to inspect.
     *
     * @return string
     */
    private function extractMajorVersion(string $version): string
    {
        if (preg_match('/([0-9]+)/', $version, $matches) === 1) {
            return $matches[1];
        }

        return '';
    }

    /**
     * Applies the relaxed constraint to a package's drupal/ai requirement.
     *
     * @param \Composer\Package\PackageInterface $package
     *   The package to update.
     * @param \Composer\Semver\Constraint\ConstraintInterface $constraint
     *   The constraint to apply.
     */
    private function adjustPackage(PackageInterface $package, \Composer\Semver\Constraint\ConstraintInterface $constraint): void
    {
        $requires = array_map(function (Link $link) use ($constraint) {
            if ($link->getDescription() === Link::TYPE_REQUIRE && $link->getTarget() === 'drupal/ai') {
                return new Link(
                    $link->getSource(),
                    $link->getTarget(),
                    $constraint,
                    $link->getDescription(),
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
