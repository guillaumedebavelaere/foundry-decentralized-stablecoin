<a name="readme-top"></a>
[![LinkedIn][linkedin-shield]][linkedin-url]

<!-- PROJECT LOGO -->
<br />
<div align="center">

<h3 align="center">Foundry decentralized stablecoin</h3>

  <p align="center">
    A decentralized stablecoin, built with solidity using foundry.
    <br />
  </p>
</div>

<!-- TABLE OF CONTENTS -->
<details>
  <summary>Table of Contents</summary>
  <ol>
    <li>
      <a href="#about-the-project">About The Project</a>
      <ul>
        <li><a href="#built-with">Built With</a></li>
      </ul>
    </li>
    <li>
      <a href="#getting-started">Getting Started</a>
      <ul>
        <li><a href="#prerequisites">Prerequisites</a></li>
        <li><a href="#quickstart">Quickstart</a></li>
      </ul>
    </li>
  </ol>
</details>

<!-- ABOUT THE PROJECT -->

## About The Project

A decentralized stablecoin that is:
- Anchored or Pegged to $1.00 (Relative stability)
  - use Chainlink to get the price feed.
  - has a function to exchange ETH or BTC against our stablecoin
- Algorithmic (Stability mechanism ie: minting / burning), so decentralized
  - People can only mint the stablecoin with enough collateral (coded)
- Exogenous (Collateral that originates from  outside the protocol: wETH, wBTC)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

### Built With

-   [![Solidity][Solidity]][Solidity-url]
-   [![Foundry][Foundry]][Foundry-url]

<p align="right">(<a href="#readme-top">back to top</a>)</p>

<!-- GETTING STARTED -->

## Getting Started

### Prerequisites

  - [Solidity](https://docs.soliditylang.org/en/develop/)
  - [Foundry](https://book.getfoundry.sh/)

<p align="right">(<a href="#readme-top">back to top</a>)</p>


<!-- MARKDOWN LINKS & IMAGES -->
<!-- https://www.markdownguide.org/basic-syntax/#reference-style-links -->

[linkedin-shield]: https://img.shields.io/badge/-LinkedIn-black.svg?style=for-the-badge&logo=linkedin&colorB=555
[linkedin-url]: https://linkedin.com/in/gdebavelaere
[product-screenshot]: images/screenshot.png
[Solidity]: https://img.shields.io/badge/-Solidity-black.svg?style=for-the-badge&logo=Solidity&colorB=555
[Solidity-url]: https://docs.soliditylang.org/en/develop/
[Foundry]: https://img.shields.io/badge/-Foundry-black.svg?style=for-the-badge&logo=Foundry&colorB=35495E
[Foundry-url]: https://book.getfoundry.sh/